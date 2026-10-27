import Foundation

struct Track: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var filename: String
    var title: String
    var artist: String = ""
    var album: String = ""
    var albumArtist: String = ""
    var genre: String = ""
    var composer: String = ""
    var year: String = ""
    var number: String = ""
    var trackTotal: String = ""
    var disc: String = ""
    var discTotal: String = ""
    var bpm: String = ""
    var comment: String = ""
    var grouping: String = ""
    var isrc: String = ""
    var lyrics: String = ""
    var artwork: String?
    var duration: Double = 0
    var sampleRate: Double = 0
    var bitDepth: Int = 0
    var favorite: Bool = false
    var imported: Date = Date()
    var lastPlayed: Date?
    var sourceName: String = ""
    var fingerprint: String = ""
    var albumKey: String { album + "\u{1f}" + (albumArtist.isEmpty ? artist : albumArtist) }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, filename, title, artist, album, albumArtist, genre, composer, year, number, trackTotal, disc, discTotal, bpm, comment, grouping, isrc, lyrics, artwork, duration, sampleRate, bitDepth, favorite, imported, lastPlayed, sourceName, fingerprint
    }
    init(id: UUID = UUID(), filename: String, title: String) { self.id = id; self.filename = filename; self.title = title }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        albumArtist = try c.decodeIfPresent(String.self, forKey: .albumArtist) ?? ""
        genre = try c.decodeIfPresent(String.self, forKey: .genre) ?? ""
        composer = try c.decodeIfPresent(String.self, forKey: .composer) ?? ""
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        trackTotal = try c.decodeIfPresent(String.self, forKey: .trackTotal) ?? ""
        disc = try c.decodeIfPresent(String.self, forKey: .disc) ?? ""
        discTotal = try c.decodeIfPresent(String.self, forKey: .discTotal) ?? ""
        bpm = try c.decodeIfPresent(String.self, forKey: .bpm) ?? ""
        comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
        grouping = try c.decodeIfPresent(String.self, forKey: .grouping) ?? ""
        isrc = try c.decodeIfPresent(String.self, forKey: .isrc) ?? ""
        lyrics = try c.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
        artwork = try c.decodeIfPresent(String.self, forKey: .artwork)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        sampleRate = try c.decodeIfPresent(Double.self, forKey: .sampleRate) ?? 0
        bitDepth = try c.decodeIfPresent(Int.self, forKey: .bitDepth) ?? 0
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        imported = try c.decodeIfPresent(Date.self, forKey: .imported) ?? Date()
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
    }
}
struct Playlist: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var tracks: [UUID] = []
}
struct LibraryState: Codable, Sendable {
    var version = 2
    var tracks: [Track] = []
    var playlists: [Playlist] = []
    static func decode(_ data: Data) throws -> LibraryState {
        if let state = try? JSONDecoder().decode(LibraryState.self, from: data) { return state }
        return LibraryState(tracks: try JSONDecoder().decode([Track].self, from: data))
    }
}
struct LyricLine: Identifiable, Equatable {
    var id: Int
    var time: Double
    var text: String
}
enum Lyrics {
    /// LRC: repeated stamps, hundredths/milliseconds, metadata and global offsets.
    static func parse(_ text: String) -> [LyricLine] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let offsetRE = try! NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\s*\]"#, options: .caseInsensitive)
        let ns = text as NSString
        var offset = 0.0
        if let m = offsetRE.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            offset = (Double(ns.substring(with: m.range(at: 1))) ?? 0) / 1000
        }
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let words = line.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let minutes = Double(line.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: m.range(at: 2))) ?? 0
                guard seconds < 60 else { continue }
                var fraction = 0.0
                if m.range(at: 3).location != NSNotFound {
                    fraction = Double("0." + line.substring(with: m.range(at: 3))) ?? 0
                }
                lines.append(LyricLine(id: lines.count, time: max(0, minutes * 60 + seconds + fraction - offset), text: words))
            }
        }
        return lines.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }
    static func active(_ lines: [LyricLine], at time: Double) -> Int? {
        lines.last(where: { $0.time <= time })?.id
    }
}
func clock(_ value: Double) -> String {
    let seconds = value.isFinite ? max(0, Int(value)) : 0
    return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
}
