import Foundation
import CryptoKit
import UIKit

struct ImportResult: Sendable { var tracks: [Track] = []; var failures: [String] = []; var duplicates = 0 }

actor FileStore {
    let root: URL
    let music: URL
    let art: URL
    let index: URL
    init(root: URL) {
        self.root = root
        music = root.appendingPathComponent("Music", isDirectory: true)
        art = root.appendingPathComponent("Artwork", isDirectory: true)
        index = root.appendingPathComponent("library.json")
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
    }
    func load() throws -> LibraryState {
        try prepare()
        guard FileManager.default.fileExists(atPath: index.path) else { return LibraryState() }
        let data = try Data(contentsOf: index)
        // Keep the original index before the first migration. Never silently overwrite a corrupt index.
        let state = try LibraryState.decode(data)
        let backup = root.appendingPathComponent("library-pre-simplex.json")
        if (try? JSONDecoder().decode([Track].self, from: data)) != nil && !FileManager.default.fileExists(atPath: backup.path) {
            try data.write(to: backup, options: .atomic)
        }
        return state
    }
    func save(_ state: LibraryState) throws {
        try prepare()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: index, options: .atomic)
    }
    func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func importFiles(_ urls: [URL], known: Set<String>, progress: @escaping @Sendable (Int, Int) async -> Void) async -> ImportResult {
        var result = ImportResult(); var seen = known
        for (position, url) in urls.enumerated() {
            await progress(position + 1, urls.count)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let id = UUID()
            let destination = music.appendingPathComponent(id.uuidString + "." + url.pathExtension.lowercased())
            do {
                guard (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory != true else { throw CocoaError(.fileReadUnsupportedScheme) }
                var copyError: Error?
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
                    do { try FileManager.default.copyItem(at: coordinatedURL, to: destination) } catch { copyError = error }
                }
                if let error = coordinationError ?? copyError as NSError? { throw error }
                let fingerprint = try hash(destination)
                if seen.contains(fingerprint) {
                    try FileManager.default.removeItem(at: destination); result.duplicates += 1; continue
                }
                try SMTags.validateURL(destination)
                var track = Track(id: id, filename: destination.lastPathComponent, title: url.deletingPathExtension().lastPathComponent)
                if let values = try? SMTags.readURL(destination) { track = try enrich(track, values: values) }
                track.sourceName = url.lastPathComponent; track.fingerprint = fingerprint
                // A matching sidecar is available when the user selects it along with the audio.
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                if let sidecar = urls.first(where: { ["lrc", "txt"].contains($0.pathExtension.lowercased()) && $0.deletingPathExtension().lastPathComponent.lowercased() == stem }) {
                    let scope = sidecar.startAccessingSecurityScopedResource()
                    defer { if scope { sidecar.stopAccessingSecurityScopedResource() } }
                    if let lyrics = try? Self.readText(sidecar) { track.lyrics = lyrics }
                }
                seen.insert(fingerprint); result.tracks.append(track)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if !["lrc", "txt"].contains(url.pathExtension.lowercased()) { result.failures.append(url.lastPathComponent + ": " + error.localizedDescription) }
            }
        }
        return result
    }
    func enrich(_ input: Track, values: [String: Any]) throws -> Track {
        var t = input
        func string(_ key: String) -> String { values[key].map { String(describing: $0) } ?? "" }
        if !string("title").isEmpty { t.title = string("title") }
        t.artist = string("artist"); t.album = string("albumTitle"); t.albumArtist = string("albumArtist")
        t.genre = string("genre"); t.composer = string("composer"); t.year = string("releaseDate")
        t.number = string("trackNumber"); t.trackTotal = string("trackTotal"); t.disc = string("discNumber"); t.discTotal = string("discTotal")
        t.bpm = string("bpm"); t.comment = string("comment"); t.grouping = string("grouping"); t.isrc = string("isrc"); t.lyrics = string("lyrics")
        t.duration = (values["duration"] as? NSNumber)?.doubleValue ?? 0
        t.sampleRate = (values["sampleRate"] as? NSNumber)?.doubleValue ?? 0
        t.bitDepth = (values["bitDepth"] as? NSNumber)?.intValue ?? 0
        if let data = values["artwork"] as? Data, let image = UIImage(data: data) {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 700, height: 700))
            let jpeg = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 700, height: 700)) }.jpegData(compressionQuality: 0.88)
            let name = t.id.uuidString + ".jpg"
            try jpeg?.write(to: art.appendingPathComponent(name), options: .atomic); t.artwork = name
        }
        return t
    }
    func edit(_ draft: Track, cover: Data?, removeCover: Bool, writeTags: Bool) throws -> Track {
        let original = music.appendingPathComponent(draft.filename)
        let temporary = music.appendingPathComponent("edit-" + UUID().uuidString + "." + original.pathExtension)
        var track = draft
        if writeTags {
            try FileManager.default.copyItem(at: original, to: temporary)
            defer { try? FileManager.default.removeItem(at: temporary) }
            var values: [String: Any] = ["title": draft.title, "artist": draft.artist, "albumTitle": draft.album, "albumArtist": draft.albumArtist, "composer": draft.composer, "genre": draft.genre, "releaseDate": draft.year, "lyrics": draft.lyrics, "comment": draft.comment, "grouping": draft.grouping, "isrc": draft.isrc]
            for (key, value) in [("trackNumber", draft.number), ("trackTotal", draft.trackTotal), ("discNumber", draft.disc), ("discTotal", draft.discTotal), ("bpm", draft.bpm)] {
                if value.isEmpty { values[key] = NSNull() }
                else if let integer = Int(value), integer >= 0 { values[key] = NSNumber(value: integer) }
                else { throw NSError(domain: "Simplex", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.s("numbersOnly")]) }
            }
            if let cover { values["artwork"] = cover }
            if removeCover { values["artwork"] = NSNull() }
            try SMTags.writeURL(temporary, values: values)
            try SMTags.validateURL(temporary)
            // Tag writes occur on a copy, then the valid result atomically replaces the library copy.
            _ = try FileManager.default.replaceItemAt(original, withItemAt: temporary)
            track.fingerprint = try hash(original)
        }
        if removeCover { track.artwork = nil }
        if let cover, let image = UIImage(data: cover), let jpeg = image.jpegData(compressionQuality: 0.9) {
            let name = UUID().uuidString + ".jpg"
            try jpeg.write(to: art.appendingPathComponent(name), options: .atomic); track.artwork = name
        }
        return track
    }
    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard data.count < 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1) { return text }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    func remove(_ track: Track) throws {
        let url = music.appendingPathComponent(track.filename)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
