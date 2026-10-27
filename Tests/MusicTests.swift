import XCTest
@testable import SimplexMusic
import UIKit
import AVFoundation

final class MusicTests: XCTestCase {
    func fixture(_ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample", withExtension: ext))
    }
    func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testLRCWithOffsetsMultipleStampsAndMetadata() {
        let lines = Lyrics.parse("[ar:Artist]\n[offset: +500]\n[00:01.50][00:03.125]Hallo 🌍\n[01:02]Ende\n[00:99]invalid")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.map(\.time), [1, 2.625, 61.5])
        XCTAssertEqual(lines[0].text, "Hallo 🌍")
        XCTAssertNil(Lyrics.active(lines, at: 0.5))
        XCTAssertEqual(Lyrics.active(lines, at: 2.7), lines[1].id)
        XCTAssertTrue(Lyrics.parse("Plain\nlyrics").isEmpty)
    }
    func testLegacyIndexMigratesWithoutLosingIDsOrFiles() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let data = Data("[{\"id\":\"\(id.uuidString)\",\"filename\":\"old.mp3\",\"title\":\"Original\"}]".utf8)
        try data.write(to: root.appendingPathComponent("library.json"))
        let store = FileStore(root: root)
        let state = try await store.load()
        XCTAssertEqual(state.tracks.first?.id, id)
        XCTAssertEqual(state.tracks.first?.filename, "old.mp3")
        XCTAssertEqual(state.tracks.first?.lyrics, "")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library-pre-simplex.json")), data)
        try await store.save(state)
        let reloaded = try await store.load()
        XCTAssertEqual(reloaded.tracks.first?.id, id)
    }
    func testCorruptIndexIsPreserved() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("broken index".utf8); let url = root.appendingPathComponent("library.json")
        try data.write(to: url)
        do { _ = try await FileStore(root: root).load(); XCTFail("Must reject corrupt index") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
    func testAllBundledFormatsDecodeAndImport() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = FileStore(root: root); try await store.prepare()
        let urls = try ["mp3", "m4a", "flac", "ogg", "opus"].map(fixture)
        let result = await store.importFiles(urls, known: []) { _, _ in }
        XCTAssertEqual(result.tracks.count, 5, result.failures.joined(separator: "\n"))
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.tracks.first?.title, "Import Test")
        XCTAssertEqual(result.tracks.first?.artist, "Simplex")
        XCTAssertTrue(result.tracks.allSatisfy { $0.duration > 0 })
        let duplicate = await store.importFiles([try fixture("mp3")], known: Set(result.tracks.map(\.fingerprint))) { _, _ in }
        XCTAssertEqual(duplicate.duplicates, 1); XCTAssertTrue(duplicate.tracks.isEmpty)
    }
    func testMP3AndFLACTagsPersistInsideAudioWithoutReencoding() async throws {
        for ext in ["mp3", "flac", "m4a", "ogg", "opus"] {
            let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
            let store = FileStore(root: root); try await store.prepare()
            let imported = await store.importFiles([try fixture(ext)], known: []) { _, _ in }
            var track = try XCTUnwrap(imported.tracks.first, imported.failures.joined(separator: "\n"))
            track.title = "Über den Wolken 🎵"; track.artist = "Robin & Raphaela"; track.album = "Simplex"
            track.number = "3"; track.genre = "Pop"; track.lyrics = "[00:00.00]Hallo\n[00:00.20]Welt"
            let cover = await MainActor.run {
                UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
                    UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
                }.jpegData(compressionQuality: 0.8)!
            }
            let changed = try await store.edit(track, cover: cover, removeCover: false, writeTags: true)
            let url = root.appendingPathComponent("Music").appendingPathComponent(changed.filename)
            let values = try SMTags.readURL(url)
            XCTAssertEqual(values["title"] as? String, track.title, ext)
            XCTAssertEqual(values["artist"] as? String, track.artist, ext)
            XCTAssertEqual(values["lyrics"] as? String, track.lyrics, ext)
            XCTAssertEqual((values["trackNumber"] as? NSNumber)?.intValue, 3, ext)
            XCTAssertNotNil(values["artwork"] as? Data, ext)
            try SMTags.validateURL(url)
            XCTAssertEqual((values["duration"] as? NSNumber)?.doubleValue ?? 0, track.duration, accuracy: 0.1, ext)
        }
    }
    func testFailedTagWriteLeavesOriginalBytes() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = FileStore(root: root); try await store.prepare()
        let result = await store.importFiles([try fixture("mp3")], known: []) { _, _ in }
        var track = try XCTUnwrap(result.tracks.first)
        let url = root.appendingPathComponent("Music").appendingPathComponent(track.filename)
        let before = try Data(contentsOf: url)
        track.number = "not a number"
        do { _ = try await store.edit(track, cover: nil, removeCover: false, writeTags: true); XCTFail("Must reject invalid tag") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testMatchingLRCIsImportedWithAudio() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Song.mp3")
        try FileManager.default.copyItem(at: fixture("mp3"), to: source)
        let sidecar = root.appendingPathComponent("Song.lrc")
        try "[00:00.12]Liedtext".write(to: sidecar, atomically: true, encoding: .utf8)
        let store = FileStore(root: root.appendingPathComponent("library")); try await store.prepare()
        let result = await store.importFiles([source, sidecar], known: []) { _, _ in }
        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.tracks.first?.lyrics, "[00:00.12]Liedtext")
        XCTAssertTrue(result.failures.isEmpty)
    }
    @MainActor func testNativeM4APlaybackAndSeeking() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        let engine = SMAudioEngine()
        try engine.startURL(fixture("m4a"))
        XCTAssertTrue(engine.playing)
        engine.pause(); XCTAssertFalse(engine.playing)
        XCTAssertTrue(engine.seek(0.12)); XCTAssertEqual(engine.time, 0.12, accuracy: 0.03)
        try engine.resume(); XCTAssertTrue(engine.playing)
        engine.stop(); XCTAssertFalse(engine.playing)
    }
    func testLanguageKeysHaveExactParity() {
        XCTAssertEqual(Set(L10n.en.keys), Set(L10n.de.keys))
        XCTAssertTrue(L10n.en.values.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(L10n.de.values.allSatisfy { !$0.isEmpty })
    }
}
