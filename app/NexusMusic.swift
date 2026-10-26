import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import MediaPlayer

@main
struct NexusMusicApp: App {
    @StateObject private var library = MusicLibrary()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(library) }
    }
}

struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    let filename: String
    let title: String
}

@MainActor final class MusicLibrary: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var tracks: [Track] = []
    @Published var current: Track?
    @Published var playing = false
    @Published var error: String?
    private var player: AVAudioPlayer?
    private let directory: URL
    private let index: URL

    override init() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("Music", isDirectory: true)
        index = root.appendingPathComponent("library.json")
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: index), let saved = try? JSONDecoder().decode([Track].self, from: data) { tracks = saved }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }
    private func save() {
        do { try JSONEncoder().encode(tracks).write(to: index, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func add(_ urls: [URL]) {
        for url in urls {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do {
                let id = UUID()
                let name = id.uuidString + "." + url.pathExtension
                try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name))
                tracks.append(Track(id: id, filename: name, title: url.deletingPathExtension().lastPathComponent))
            } catch { self.error = error.localizedDescription }
        }
        save()
    }
    func play(_ track: Track) {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: directory.appendingPathComponent(track.filename))
            player?.delegate = self
            guard player?.play() == true else { throw NSError(domain: "Playback", code: 1) }
            current = track; playing = true
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: track.title]
        } catch { self.error = error.localizedDescription }
    }
    func toggle() {
        guard let player else { return }
        if player.isPlaying { player.pause(); playing = false } else { playing = player.play() }
    }
    func remove(_ offsets: IndexSet) {
        for i in offsets {
            let track = tracks[i]
            if current?.id == track.id { player?.stop(); current = nil; playing = false }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(track.filename))
        }
        tracks.remove(atOffsets: offsets); save()
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false }
    }
}

struct DeezerResponse: Decodable { let data: [DeezerTrack] }
struct DeezerTrack: Decodable, Identifiable {
    struct Artist: Decodable { let name: String }
    let id: Int
    let title: String
    let artist: Artist
    let preview: URL?
}

struct ContentView: View {
    @EnvironmentObject var library: MusicLibrary
    @AppStorage("welcomeSeen") private var welcomeSeen = false
    @State private var importing = false
    @State private var query = ""
    @State private var results: [DeezerTrack] = []
    @State private var searchError: String?
    @State private var loading = false
    @State private var previewPlayer: AVPlayer?
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    if library.tracks.isEmpty {
                        ContentUnavailableView("Noch keine Musik", systemImage: "music.note.list", description: Text("Importiere Audiodateien über die Dateien-App."))
                    }
                    ForEach(library.tracks) { track in
                        Button { library.play(track) } label: {
                            HStack { Image(systemName: "music.note").frame(width: 36); Text(track.title); Spacer(); if library.current?.id == track.id { Image(systemName: "waveform") } }
                        }.foregroundStyle(.primary)
                    }.onDelete(perform: library.remove)
                }
                .navigationTitle("Mediathek")
                .toolbar { Button { importing = true } label: { Image(systemName: "plus") }.accessibilityLabel("Musik importieren") }
                .safeAreaInset(edge: .bottom) {
                    if let current = library.current {
                        HStack { Image(systemName: "music.note"); Text(current.title).lineLimit(1); Spacer(); Button { library.toggle() } label: { Image(systemName: library.playing ? "pause.fill" : "play.fill") } }
                            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal)
                    }
                }
            }.tabItem { Label("Mediathek", systemImage: "music.note.list") }
            NavigationStack {
                List {
                    if loading { ProgressView() }
                    if let searchError { Text(searchError).foregroundStyle(.secondary) }
                    ForEach(results) { track in
                        HStack {
                            VStack(alignment: .leading) { Text(track.title); Text(track.artist.name).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if let url = track.preview { Button { previewPlayer = AVPlayer(url: url); previewPlayer?.play() } label: { Image(systemName: "play.circle") }.accessibilityLabel("Hörprobe abspielen") }
                        }
                    }
                }
                .navigationTitle("Entdecken")
                .searchable(text: $query, prompt: "Titel oder Künstler suchen")
                .onSubmit(of: .search) { Task { await search() } }
                .overlay { if results.isEmpty && !loading && searchError == nil { ContentUnavailableView("Musik entdecken", systemImage: "magnifyingglass", description: Text("Suche im öffentlichen Deezer-Katalog nach Hörproben.")) } }
            }.tabItem { Label("Entdecken", systemImage: "magnifyingglass") }
            NavigationStack {
                Form {
                    Section("Über die App") { Text("Deine importierten Dateien bleiben auf diesem Gerät."); Text("Die Suche benötigt eine Internetverbindung zu Deezer.") }
                    Section("Funktionen") { Text("Deezer-Anmeldung, vollständige Downloads und Datenbankübernahme sind noch nicht verfügbar.") }
                }.navigationTitle("Einstellungen")
            }.tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): library.add(urls); case .failure(let error): library.error = error.localizedDescription }
        }
        .alert("Fehler", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button("OK") { library.error = nil } } message: { Text(library.error ?? "") }
        .sheet(isPresented: Binding(get: { !welcomeSeen }, set: { if !$0 { welcomeSeen = true } })) {
            VStack(spacing: 24) { Image(systemName: "music.note.house.fill").font(.system(size: 70)).foregroundStyle(.tint); Text("Willkommen bei NEXUS Musik").font(.largeTitle.bold()).multilineTextAlignment(.center); Text("Importiere deine Musik und entdecke Hörproben. Deine Mediathek bleibt auf deinem iPhone.").multilineTextAlignment(.center).foregroundStyle(.secondary); Button("Los geht’s") { welcomeSeen = true }.buttonStyle(.borderedProminent).controlSize(.large) }.padding(32)
        }
    }
    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { results = []; return }
        loading = true; searchError = nil
        defer { loading = false }
        do {
            var components = URLComponents(string: "https://api.deezer.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: term)]
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            results = try JSONDecoder().decode(DeezerResponse.self, from: data).data
        } catch { searchError = error.localizedDescription }
    }
}
