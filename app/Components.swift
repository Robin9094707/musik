import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MediaPlayer
import AVKit

struct DocumentPicker: UIViewControllerRepresentable {
    var multiple = true
    var onPick: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // .item allows selection even when a provider reports audio as generic data.
        // asCopy downloads provider/iCloud files and gives us a readable local copy.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) }
    }
}
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.activeTintColor = .systemCyan; view.prioritizesVideoDevices = false; return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
struct SystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(); view.showsRouteButton = false; return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
struct Artwork: View {
    @EnvironmentObject var library: MusicLibrary
    var track: Track?
    var size: CGFloat = 56
    var radius: CGFloat = 12
    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple.opacity(0.8), .cyan.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let track, let url = library.artworkURL(track) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { symbol }
            } else { symbol }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.12), lineWidth: 0.7))
        .accessibilityHidden(true)
    }
    var symbol: some View { Image(systemName: "music.note").font(.system(size: size * 0.35, weight: .medium)).foregroundStyle(.white.opacity(0.9)) }
}
struct MusicBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(uiColor: .systemGroupedBackground)
            Ellipse().fill(.indigo.opacity(scheme == .dark ? 0.25 : 0.1)).frame(width: 360, height: 420).blur(radius: 90).offset(x: 120, y: -150)
            Ellipse().fill(.cyan.opacity(0.08)).frame(width: 280, height: 300).blur(radius: 80).offset(x: -180, y: 450)
        }.ignoresSafeArea()
    }
}
struct MiniPlayer: View {
    @EnvironmentObject var library: MusicLibrary
    var open: () -> Void
    var body: some View {
        if let track = library.current {
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        Artwork(track: track, size: 42, radius: 9)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(track.artist.isEmpty ? t("unknownArtist") : track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(t("nowPlaying") + ": " + track.title)
                Button { library.toggle() } label: { Image(systemName: library.playing ? "pause.fill" : "play.fill").font(.title3).frame(width: 38, height: 44) }.buttonStyle(.plain).accessibilityLabel(t(library.playing ? "pause" : "play"))
                Button { library.next() } label: { Image(systemName: "forward.fill").frame(width: 34, height: 44) }.buttonStyle(.plain).accessibilityLabel(t("playNext"))
            }.padding(.horizontal, 14).padding(.vertical, 6)
        }
    }
}
struct TrackRow: View {
    @EnvironmentObject var library: MusicLibrary
    let track: Track
    var body: some View {
        HStack(spacing: 13) {
            Artwork(track: track, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.body.weight(.medium)).foregroundStyle(library.currentID == track.id ? Color.accentColor : .primary).lineLimit(1)
                Text(track.artist.isEmpty ? t("unknownArtist") : track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if track.favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.tint) }
            if library.currentID == track.id && library.playing { Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(.tint) }
            else { Text(clock(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary) }
        }.padding(.vertical, 3).contentShape(Rectangle())
    }
}
struct TrackActions: View {
    @EnvironmentObject var library: MusicLibrary
    let track: Track
    let edit: () -> Void
    let delete: () -> Void
    var body: some View {
        Button { library.favorite(track.id) } label: { Label(t(track.favorite ? "unfavorite" : "favorite"), systemImage: track.favorite ? "star.slash" : "star") }
        if library.current != nil { Button { library.playNext(track) } label: { Label(t("playNext"), systemImage: "text.line.first.and.arrowtriangle.forward") } }
        Menu {
            ForEach(library.state.playlists) { playlist in
                Button(playlist.name) { library.addToPlaylist(track, playlist: playlist.id) }
            }
        } label: { Label(t("addPlaylist"), systemImage: "text.badge.plus") }.disabled(library.state.playlists.isEmpty)
        Button(action: edit) { Label(t("edit"), systemImage: "slider.horizontal.3") }
        ShareLink(item: library.url(track), preview: SharePreview(track.title)) { Label(t("share"), systemImage: "square.and.arrow.up") }
        Button(role: .destructive, action: delete) { Label(t("delete"), systemImage: "trash") }
    }
}
struct TrackCollection: View {
    @EnvironmentObject var library: MusicLibrary
    let title: String
    let tracks: [Track]
    @State private var editing: Track?
    @State private var deleting: Track?
    var body: some View {
        List {
            if !tracks.isEmpty {
                HStack {
                    Button { if let first = tracks.first { library.play(first, within: tracks) } } label: { Label(t("play"), systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent)
                    Button { if let first = tracks.randomElement() { if !library.shuffled { library.shuffle() }; library.play(first, within: tracks) } } label: { Label(t("shuffle"), systemImage: "shuffle").frame(maxWidth: .infinity) }.buttonStyle(.glass)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 16, trailing: 0))
            }
            ForEach(tracks) { track in
                Button { library.play(track, within: tracks) } label: { TrackRow(track: track) }.buttonStyle(.plain)
                    .contextMenu { TrackActions(track: track, edit: { editing = track }, delete: { deleting = track }) }
                    .swipeActions(edge: .trailing) { Button(role: .destructive) { deleting = track } label: { Label(t("delete"), systemImage: "trash") } }
                    .swipeActions(edge: .leading) { Button { library.favorite(track.id) } label: { Label(t("favorite"), systemImage: "star") }.tint(.indigo) }
            }
        }.scrollContentBackground(.hidden).background { MusicBackground() }.navigationTitle(title)
            .overlay { if tracks.isEmpty { ContentUnavailableView(t("noResults"), systemImage: "music.note") } }
            .sheet(item: $editing) { TagEditor(track: $0) }
            .confirmationDialog(t("deleteTitle"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(t("delete"), role: .destructive) { if let track = deleting { Task { await library.delete(track) } }; deleting = nil }
            } message: { Text(t("deleteBody")) }
    }
}
