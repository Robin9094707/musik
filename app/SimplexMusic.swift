import SwiftUI

@main struct SimplexMusicApp: App {
    @StateObject private var library = MusicLibrary()
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("theme") private var theme = "system"
    var body: some Scene {
        WindowGroup {
            RootView().id(language).environmentObject(library)
                .environment(\.locale, Locale(identifier: L10n.language))
                .preferredColorScheme(theme == "system" ? nil : theme == "dark" ? .dark : .light)
                .tint(Color(red: 0.44, green: 0.42, blue: 1))
        }
    }
}
struct RootView: View {
    @EnvironmentObject var library: MusicLibrary
    @Environment(\.scenePhase) private var phase
    @AppStorage("simplexWelcomeSeen") private var welcomeSeen = false
    @State private var picker = false
    @State private var player = false
    var body: some View {
        TabView {
            Tab(t("library"), systemImage: "music.note.house.fill") { LibraryView(importMusic: { picker = true }) }
            Tab(t("playlists"), systemImage: "square.stack.fill") { PlaylistsView() }
            Tab(t("settings"), systemImage: "gearshape.fill") { SettingsView() }
        }
        .tabViewBottomAccessory(isEnabled: library.current != nil) { MiniPlayer { player = true } }
        .sheet(isPresented: $picker) {
            DocumentPicker { urls in picker = false; Task { await library.add(urls) } }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $player) { PlayerView() }
        .fullScreenCover(isPresented: Binding(get: { !welcomeSeen && !ProcessInfo.processInfo.arguments.contains("--ui-testing") }, set: { if !$0 { welcomeSeen = true } })) { WelcomeView { welcomeSeen = true } }
        .alert(t("error"), isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button(t("ok")) { library.error = nil }
        } message: { Text(library.error ?? "") }
        .alert(t("importDone"), isPresented: Binding(get: { library.notice != nil }, set: { if !$0 { library.notice = nil } })) {
            Button(t("ok")) { library.notice = nil }
        } message: { Text(library.notice ?? "") }
        .overlay(alignment: .top) {
            if library.importing {
                HStack(spacing: 14) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("importing")).font(.subheadline.bold())
                        Text(String(format: t("importProgress"), library.importPosition, library.importTotal)).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: Double(library.importPosition), total: Double(max(1, library.importTotal)))
                    }
                }.padding(18).glassEffect(.regular, in: .rect(cornerRadius: 24)).padding().accessibilityElement(children: .combine)
            }
        }
        .onOpenURL { url in Task { while !library.ready { try? await Task.sleep(for: .milliseconds(50)) }; await library.add([url]) } }
        .onChange(of: phase) { _, value in if value == .background { library.persist() } }
    }
}
struct LibraryView: View {
    @EnvironmentObject var library: MusicLibrary
    let importMusic: () -> Void
    @State private var query = ""
    @State private var shelf = "songs"
    @State private var sort = "dateAdded"
    @State private var editing: Track?
    @State private var deleting: Track?
    private let shelves = ["songs", "albums", "artists", "favorites"]
    var filtered: [Track] {
        var items = library.tracks.filter { track in
            (shelf != "favorites" || track.favorite) && (query.isEmpty || [track.title, track.artist, track.album, track.genre].contains { $0.localizedCaseInsensitiveContains(query) })
        }
        switch sort {
        case "title": items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case "artist": items.sort { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        case "duration": items.sort { $0.duration > $1.duration }
        default: items.sort { $0.imported > $1.imported }
        }
        return items
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    hero
                    if library.tracks.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 54, weight: .light)).foregroundStyle(.tint)
                            Text(t("emptyTitle")).font(.title2.bold())
                            Text(t("emptyBody")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button(action: importMusic) { Label(t("import"), systemImage: "plus").padding(.horizontal, 12).padding(.vertical, 5) }.buttonStyle(.glassProminent).accessibilityIdentifier("importMusicEmpty")
                        }.frame(maxWidth: .infinity).padding(30).glassEffect(.regular, in: .rect(cornerRadius: 30))
                    } else {
                        if query.isEmpty && shelf == "songs" { recent }
                        shelfPicker
                        HStack {
                            Text(t(shelf == "songs" ? "allMusic" : shelf)).font(.title2.bold())
                            Spacer()
                            Menu { Picker(t("sort"), selection: $sort) { ForEach(["dateAdded", "title", "artist", "duration"], id: \.self) { Text(t($0)).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down").padding(10) }.buttonStyle(.glass).accessibilityLabel(t("sort"))
                        }
                        collection
                    }
                }.padding(.horizontal, 20).padding(.bottom, 24)
            }.background { MusicBackground() }
                .navigationTitle("Simplex").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: t("search"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button(action: importMusic) { Image(systemName: "plus") }.accessibilityLabel(t("import")).accessibilityIdentifier("importMusic").disabled(library.importing || !library.ready) }
                }
                .sheet(item: $editing) { TagEditor(track: $0) }
                .confirmationDialog(t("deleteTitle"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button(t("delete"), role: .destructive) { if let track = deleting { Task { await library.delete(track) } }; deleting = nil }
                } message: { Text(t("deleteBody")) }
        }
    }
    var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) { Circle().fill(.cyan).frame(width: 6, height: 6); Text(t("onDevice").uppercased()).font(.caption2.weight(.bold)).tracking(2).foregroundStyle(.secondary) }
            Text(t("hero")).font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.8).fixedSize(horizontal: false, vertical: true)
            Text(t("heroSub")).font(.subheadline).foregroundStyle(.secondary)
            if !library.tracks.isEmpty {
                HStack(spacing: 16) {
                    Text(String(format: t("songCount"), library.tracks.count)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { if let first = filtered.first { library.play(first, within: filtered) } } label: { Label(t("play"), systemImage: "play.fill").padding(.horizontal, 5) }.buttonStyle(.glassProminent)
                    Button { if let first = filtered.randomElement() { if !library.shuffled { library.shuffle() }; library.play(first, within: filtered) } } label: { Image(systemName: "shuffle") }.buttonStyle(.glass).accessibilityLabel(t("shuffle"))
                }.padding(.top, 5)
            }
        }.padding(.top, 15).padding(.bottom, 4)
    }
    var recent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(t("recent")).font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(library.tracks.sorted { $0.imported > $1.imported }.prefix(12))) { track in
                        Button { library.play(track, within: filtered) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Artwork(track: track, size: 150, radius: 22).shadow(color: .black.opacity(0.13), radius: 12, y: 8)
                                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(track.artist.isEmpty ? t("unknownArtist") : track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 150, alignment: .leading).padding(.bottom, 10)
                        }.buttonStyle(.plain).contextMenu { TrackActions(track: track, edit: { editing = track }, delete: { deleting = track }) }
                    }
                }
            }.contentMargins(.vertical, 2)
        }
    }
    var shelfPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shelves, id: \.self) { item in
                    Button { withAnimation(.snappy) { shelf = item } } label: { Text(t(item)).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 11).foregroundStyle(shelf == item ? Color.white : Color.primary).background(shelf == item ? Color.accentColor : Color.clear, in: Capsule()) }
                        .buttonStyle(.plain).glassEffect(.regular, in: .capsule).accessibilityAddTraits(shelf == item ? .isSelected : [])
                }
            }.padding(.vertical, 2)
        }
    }
    @ViewBuilder var collection: some View {
        if filtered.isEmpty {
            ContentUnavailableView(t(shelf == "favorites" ? "emptyFavorites" : "noResults"), systemImage: shelf == "favorites" ? "star" : "magnifyingglass", description: Text(shelf == "favorites" ? t("emptyFavoritesBody") : ""))
        } else if shelf == "albums" {
            let groups = Dictionary(grouping: filtered, by: \.albumKey)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 18)], spacing: 24) {
                ForEach(groups.keys.sorted(), id: \.self) { key in
                    let tracks = (groups[key] ?? []).sorted { (Int($0.disc) ?? 0, Int($0.number) ?? 0) < (Int($1.disc) ?? 0, Int($1.number) ?? 0) }
                    if let first = tracks.first {
                        NavigationLink { TrackCollection(title: first.album.isEmpty ? t("unknownAlbum") : first.album, tracks: library.tracks.filter { $0.albumKey == key }.sorted { (Int($0.disc) ?? 0, Int($0.number) ?? 0) < (Int($1.disc) ?? 0, Int($1.number) ?? 0) }) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Artwork(track: first, size: 150, radius: 20)
                                Text(first.album.isEmpty ? t("unknownAlbum") : first.album).font(.subheadline.bold()).lineLimit(1)
                                Text(first.albumArtist.isEmpty ? first.artist : first.albumArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
        } else if shelf == "artists" {
            let groups = Dictionary(grouping: filtered, by: \.artist)
            ForEach(groups.keys.sorted(), id: \.self) { artist in
                NavigationLink { TrackCollection(title: artist.isEmpty ? t("unknownArtist") : artist, tracks: library.tracks.filter { $0.artist == artist }) } label: {
                    HStack(spacing: 14) {
                        Artwork(track: groups[artist]?.first, size: 60, radius: 30)
                        VStack(alignment: .leading, spacing: 4) { Text(artist.isEmpty ? t("unknownArtist") : artist).font(.headline); Text(String(format: t("songCount"), groups[artist]?.count ?? 0)).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { track in
                    HStack {
                        Button { library.play(track, within: filtered) } label: { TrackRow(track: track) }.buttonStyle(.plain)
                        Menu { TrackActions(track: track, edit: { editing = track }, delete: { deleting = track }) } label: { Image(systemName: "ellipsis").frame(width: 36, height: 48).contentShape(Rectangle()) }.accessibilityLabel(t("details"))
                    }.contextMenu { TrackActions(track: track, edit: { editing = track }, delete: { deleting = track }) }
                    Divider().padding(.leading, 65)
                }
            }
        }
    }
}
