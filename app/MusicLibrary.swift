import SwiftUI
import AVFoundation
import MediaPlayer
import Combine

@MainActor final class MusicLibrary: ObservableObject {
    @Published var state = LibraryState()
    @Published var currentID: UUID?
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var queue: [UUID] = []
    @Published var shuffled = false
    @Published var repeatMode = 0 // off, all, one
    @Published var error: String?
    @Published var notice: String?
    @Published var importing = false
    @Published var importPosition = 0
    @Published var importTotal = 0
    @Published var ready = false
    @Published var sleepDate: Date?
    private var playbackEnded = false
    private var writesAllowed = true
    private var persistTask: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var unshuffledQueue: [UUID] = []
    let root: URL
    let store: FileStore
    private let engine = SMAudioEngine()
    var tracks: [Track] { state.tracks }
    var current: Track? { state.tracks.first { $0.id == currentID } }
    var upcoming: [Track] {
        guard let currentID, let i = queue.firstIndex(of: currentID), i + 1 < queue.count else { return [] }
        return queue[(i + 1)...].compactMap { id in tracks.first { $0.id == id } }
    }
    init(root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.root = root; store = FileStore(root: root)
        engine.onEnd = { [weak self] in self?.finished() }
        engine.onError = { [weak self] message in self?.playing = false; self?.error = message }
        engine.onState = { [weak self] playing in self?.playing = playing; self?.nowPlaying() }
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default) }
        catch { self.error = error.localizedDescription }
        timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            if self.engine.playing { self.position = self.engine.time; self.duration = max(self.engine.duration, self.current?.duration ?? 0) }
            if let date = self.sleepDate, date <= Date() { self.pause(); self.sleepDate = nil }
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor in self?.seek(seconds) }; return .success
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
        Task { await load() }
    }
    func load() async {
        do { state = try await store.load() }
        catch { writesAllowed = false; self.error = L10n.s("indexError") + "\n" + error.localizedDescription }
        ready = true
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && tracks.isEmpty { await seedPreview() }
    }
    func url(_ track: Track) -> URL { root.appendingPathComponent("Music").appendingPathComponent(track.filename) }
    func artworkURL(_ track: Track) -> URL? { track.artwork.map { root.appendingPathComponent("Artwork").appendingPathComponent($0) } }
    func persist() {
        guard writesAllowed, ready else { return }
        persistTask?.cancel()
        let snapshot = state
        persistTask = Task {
            // Actor writes remain ordered; canceled tasks are dropped before entering the store.
            guard !Task.isCancelled else { return }
            do { try await store.save(snapshot) } catch { self.error = error.localizedDescription }
        }
    }
    func flush() async { await persistTask?.value }
    func add(_ urls: [URL]) async {
        guard ready, writesAllowed, !importing else { return }
        importing = true; importPosition = 0; importTotal = urls.count
        let result = await store.importFiles(urls, known: Set(tracks.map(\.fingerprint).filter { !$0.isEmpty })) { [weak self] current, total in
            await MainActor.run { self?.importPosition = current; self?.importTotal = total }
        }
        state.tracks.append(contentsOf: result.tracks); persist(); await flush(); importing = false
        var message = String(format: L10n.s("importReport"), result.tracks.count, result.duplicates)
        if !result.failures.isEmpty { message += "\n\n" + L10n.s("importFailures") + "\n" + result.failures.joined(separator: "\n") }
        notice = message
        UINotificationFeedbackGenerator().notificationOccurred(result.failures.isEmpty ? .success : .warning)
    }
    func play(_ track: Track, within list: [Track]? = nil) {
        if let list {
            unshuffledQueue = list.map(\.id)
            queue = shuffled ? [track.id] + unshuffledQueue.filter { $0 != track.id }.shuffled() : unshuffledQueue
        } else if !queue.contains(track.id) { queue = tracks.map(\.id); unshuffledQueue = queue }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.startURL(url(track))
            currentID = track.id; playbackEnded = false; playing = true; position = 0; duration = track.duration
            if let i = state.tracks.firstIndex(where: { $0.id == track.id }) { state.tracks[i].lastPlayed = Date(); persist() }
            nowPlaying(); UISelectionFeedbackGenerator().selectionChanged()
        } catch { self.error = error.localizedDescription; playing = false }
    }
    func pause() { engine.pause(); playing = false; nowPlaying() }
    func resume() {
        if playbackEnded, let track = current { play(track); return }
        guard currentID != nil else { if let first = tracks.first { play(first, within: tracks) }; return }
        do { try AVAudioSession.sharedInstance().setActive(true); try engine.resume(); playing = true; nowPlaying() }
        catch { self.error = error.localizedDescription }
    }
    func toggle() { playing ? pause() : resume() }
    func seek(_ seconds: Double) { _ = engine.seek(max(0, min(seconds, max(0, duration - 0.01)))); position = max(0, min(seconds, duration)); nowPlaying() }
    func next() {
        guard let id = currentID, let i = queue.firstIndex(of: id) else { return }
        let nextIndex = i + 1
        if nextIndex < queue.count, let track = tracks.first(where: { $0.id == queue[nextIndex] }) { play(track) }
        else if repeatMode == 1, let first = queue.first, let track = tracks.first(where: { $0.id == first }) { play(track) }
        else { pause() }
    }
    func previous() {
        if position > 3 { seek(0); return }
        guard let id = currentID, let i = queue.firstIndex(of: id) else { return }
        if i > 0, let track = tracks.first(where: { $0.id == queue[i - 1] }) { play(track) } else { seek(0) }
    }
    private func finished() {
        playbackEnded = true
        if repeatMode == 2, let track = current { play(track) } else { next() }
    }
    func shuffle() {
        shuffled.toggle()
        if shuffled, let id = currentID { unshuffledQueue = queue; queue = [id] + queue.filter { $0 != id }.shuffled() }
        else if !unshuffledQueue.isEmpty { queue = unshuffledQueue }
    }
    func playNext(_ track: Track) {
        guard let id = currentID, let i = queue.firstIndex(of: id), track.id != id else { return }
        queue.removeAll { $0 == track.id }
        let insertion = (queue.firstIndex(of: id) ?? i) + 1
        queue.insert(track.id, at: min(insertion, queue.count))
    }
    func removeUpcoming(_ id: UUID) { guard id != currentID else { return }; queue.removeAll { $0 == id } }
    func favorite(_ id: UUID) {
        guard let i = state.tracks.firstIndex(where: { $0.id == id }) else { return }
        state.tracks[i].favorite.toggle(); persist(); UISelectionFeedbackGenerator().selectionChanged()
    }
    func delete(_ track: Track) async {
        if track.id == currentID { engine.stop(); currentID = nil; playing = false; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        do {
            try await store.remove(track)
            state.tracks.removeAll { $0.id == track.id }; queue.removeAll { $0 == track.id }
            for i in state.playlists.indices { state.playlists[i].tracks.removeAll { $0 == track.id } }
            persist()
        } catch { self.error = error.localizedDescription }
    }
    func saveEdit(_ track: Track, cover: Data?, removeCover: Bool, writeTags: Bool) async throws {
        let wasCurrent = currentID == track.id
        let oldPosition = position; let wasPlaying = playing
        if wasCurrent && writeTags { engine.stop(); playing = false }
        do {
            let edited = try await store.edit(track, cover: cover, removeCover: removeCover, writeTags: writeTags)
            if let i = state.tracks.firstIndex(where: { $0.id == track.id }) { state.tracks[i] = edited }
            persist(); await flush()
            if wasCurrent && writeTags { play(edited); seek(oldPosition); if !wasPlaying { pause() } }
            nowPlaying()
        } catch {
            if wasCurrent && writeTags { play(track); seek(oldPosition); if !wasPlaying { pause() } }
            throw error
        }
    }
    func createPlaylist(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        state.playlists.append(Playlist(name: clean)); persist()
    }
    func addToPlaylist(_ track: Track, playlist: UUID) {
        guard let i = state.playlists.firstIndex(where: { $0.id == playlist }), !state.playlists[i].tracks.contains(track.id) else { return }
        state.playlists[i].tracks.append(track.id); persist()
    }
    func nowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0]
        if let url = artworkURL(track), let image = UIImage(contentsOfFile: url.path) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func seedPreview() async {
        let files: [(String, String, String)] = [("Afterglow", "Simplex Sessions", "Night Drive"), ("Blue Hour", "Simplex Sessions", "Night Drive"), ("Still Water", "Studio North", "Quiet Places")]
        for (i, info) in files.enumerated() {
            let name = "preview-\(i).wav"; let url = root.appendingPathComponent("Music/" + name)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 8) {
                buffer.frameLength = buffer.frameCapacity
                for f in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][f] = Float(sin(Double(f) * 2 * .pi * (220 + Double(i) * 55) / 44100) * 0.025) }
                if let file = try? AVAudioFile(forWriting: url, settings: format.settings) { try? file.write(from: buffer) }
            }
            var track = Track(filename: name, title: info.0); track.artist = info.1; track.album = info.2; track.duration = 8; track.sampleRate = 44100; track.favorite = i == 0
            track.lyrics = "[00:00.00]Your music. Your world.\n[00:02.00]A little closer to the sound.\n[00:04.00]Every moment has a melody.\n[00:06.00]Take it with you."
            state.tracks.append(track)
        }
        persist()
    }
}
