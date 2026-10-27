import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var library: MusicLibrary
    @State private var creating = false
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { TrackCollection(title: t("favorites"), tracks: library.tracks.filter(\.favorite)) } label: {
                    HStack(spacing: 16) { Image(systemName: "star.fill").font(.title).foregroundStyle(.indigo).frame(width: 60, height: 60).background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 15)); VStack(alignment: .leading, spacing: 5) { Text(t("favorites")).font(.headline); Text(String(format: t("songCount"), library.tracks.filter(\.favorite).count)).font(.caption).foregroundStyle(.secondary) } }
                }
                ForEach(library.state.playlists) { playlist in
                    NavigationLink { PlaylistDetail(id: playlist.id) } label: {
                        HStack(spacing: 16) {
                            Artwork(track: playlist.tracks.first.flatMap { id in library.tracks.first { $0.id == id } }, size: 60, radius: 15)
                            VStack(alignment: .leading, spacing: 5) { Text(playlist.name).font(.headline); Text(String(format: t("songCount"), playlist.tracks.count)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if library.state.playlists.isEmpty {
                    ContentUnavailableView(t("emptyPlaylists"), systemImage: "square.stack", description: Text(t("emptyPlaylistsBody"))).listRowBackground(Color.clear)
                    Button { name = ""; creating = true } label: { Label(t("newPlaylist"), systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).listRowBackground(Color.clear)
                }
            }.scrollContentBackground(.hidden).background { MusicBackground() }.navigationTitle(t("playlists"))
                .toolbar { Button { name = ""; creating = true } label: { Image(systemName: "plus") }.accessibilityLabel(t("newPlaylist")) }
                .alert(t("newPlaylist"), isPresented: $creating) {
                    TextField(t("playlistName"), text: $name)
                    Button(t("create")) { library.createPlaylist(name) }; Button(t("cancel"), role: .cancel) {}
                }
        }
    }
}
struct PlaylistDetail: View {
    @EnvironmentObject var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var adding = false
    @State private var renaming = false
    @State private var deleting = false
    @State private var name = ""
    @State private var editing: Track?
    var playlist: Playlist? { library.state.playlists.first { $0.id == id } }
    var songs: [Track] { (playlist?.tracks ?? []).compactMap { id in library.tracks.first { $0.id == id } } }
    var body: some View {
        List {
            HStack {
                Button { if let first = songs.first { library.play(first, within: songs) } } label: { Label(t("play"), systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).disabled(songs.isEmpty)
                Button { adding = true } label: { Label(t("addSongs"), systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.glass)
            }.listRowBackground(Color.clear)
            ForEach(songs) { track in
                Button { library.play(track, within: songs) } label: { TrackRow(track: track) }.buttonStyle(.plain)
                    .contextMenu { Button(t("edit")) { editing = track }; Button(t("remove"), role: .destructive) { remove(track.id) } }
            }.onDelete { offsets in let ids = offsets.map { songs[$0].id }; for id in ids { remove(id) } }
                .onMove { source, destination in
                    if let i = library.state.playlists.firstIndex(where: { $0.id == id }) { library.state.playlists[i].tracks.move(fromOffsets: source, toOffset: destination); library.persist() }
                }
            if songs.isEmpty { ContentUnavailableView(t("emptyPlaylist"), systemImage: "music.note.list").listRowBackground(Color.clear) }
        }.scrollContentBackground(.hidden).background { MusicBackground() }.navigationTitle(playlist?.name ?? t("playlists"))
            .toolbar {
                EditButton()
                Menu {
                    Button(t("addSongs")) { adding = true }
                    Button(t("rename")) { name = playlist?.name ?? ""; renaming = true }
                    Button(t("delete"), role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel(t("details"))
            }
            .sheet(isPresented: $adding) { PlaylistSongPicker(playlistID: id) }
            .sheet(item: $editing) { TagEditor(track: $0) }
            .alert(t("rename"), isPresented: $renaming) {
                TextField(t("playlistName"), text: $name)
                Button(t("save")) {
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty, let i = library.state.playlists.firstIndex(where: { $0.id == id }) { library.state.playlists[i].name = clean; library.persist() }
                }; Button(t("cancel"), role: .cancel) {}
            }
            .confirmationDialog(t("playlistDelete"), isPresented: $deleting, titleVisibility: .visible) {
                Button(t("delete"), role: .destructive) { library.state.playlists.removeAll { $0.id == id }; library.persist(); dismiss() }
            } message: { Text(t("playlistDeleteBody")) }
    }
    func remove(_ trackID: UUID) { if let i = library.state.playlists.firstIndex(where: { $0.id == id }) { library.state.playlists[i].tracks.removeAll { $0 == trackID }; library.persist() } }
}
struct PlaylistSongPicker: View {
    @EnvironmentObject var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    let playlistID: UUID
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List(library.tracks.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }) { track in
                let selected = library.state.playlists.first(where: { $0.id == playlistID })?.tracks.contains(track.id) ?? false
                Button {
                    if selected, let i = library.state.playlists.firstIndex(where: { $0.id == playlistID }) { library.state.playlists[i].tracks.removeAll { $0 == track.id }; library.persist() }
                    else { library.addToPlaylist(track, playlist: playlistID) }
                } label: { HStack { TrackRow(track: track); Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(.tint) } }.buttonStyle(.plain)
            }.navigationTitle(t("addSongs")).searchable(text: $query, prompt: t("search"))
                .toolbar { Button(t("done")) { dismiss() } }
        }
    }
}
