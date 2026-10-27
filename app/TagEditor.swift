import SwiftUI
import PhotosUI

struct TagEditor: View {
    @EnvironmentObject var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    let original: Track
    @State private var draft: Track
    @State private var cover: Data?
    @State private var removeCover = false
    @State private var photo: PhotosPickerItem?
    @State private var picker = false
    @State private var pickerKind = "lyrics"
    @State private var writeTags = true
    @State private var saving = false
    @State private var error: String?
    init(track: Track) { original = track; _draft = State(initialValue: track) }
    var body: some View {
        NavigationStack {
            Form {
                coverSection
                Section(t("metadata")) {
                    field("title", \.title); field("artist", \.artist); field("album", \.album); field("albumArtist", \.albumArtist)
                    field("composer", \.composer); field("genre", \.genre); field("year", \.year)
                }
                Section {
                    field("trackNumber", \.number, number: true); field("trackTotal", \.trackTotal, number: true)
                    field("discNumber", \.disc, number: true); field("discTotal", \.discTotal, number: true); field("bpm", \.bpm, number: true)
                    field("grouping", \.grouping); field("isrc", \.isrc); field("comment", \.comment)
                }
                Section {
                    Button { pickerKind = "lyrics"; picker = true } label: { Label(t("importLyrics"), systemImage: "doc.text") }
                    TextEditor(text: $draft.lyrics).frame(minHeight: 220).font(.body.monospaced()).accessibilityLabel(t("lyricsInfo"))
                    Text(draft.lyrics.isEmpty ? t("lyricsPlaceholder") : t(Lyrics.parse(draft.lyrics).isEmpty ? "plainLyrics" : "syncedLyrics")).font(.caption).foregroundStyle(.secondary)
                } header: { Text(t("lyricsInfo")) } footer: { Text(t("lyricsHelp")) }
                Section {
                    Toggle(t("writeFile"), isOn: $writeTags)
                } footer: { Text(t("writeFileHint")) }
                Section(t("technical")) {
                    LabeledContent(t("file"), value: draft.sourceName.isEmpty ? draft.filename : draft.sourceName)
                    LabeledContent(t("duration"), value: clock(draft.duration))
                    LabeledContent(t("sampleRate"), value: String(format: "%.1f kHz", draft.sampleRate / 1000))
                    if draft.bitDepth > 0 { LabeledContent(t("bitDepth"), value: "\(draft.bitDepth) bit") }
                    if let bytes = (try? library.url(draft).resourceValues(forKeys: [.fileSizeKey]))?.fileSize { LabeledContent(t("size"), value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) }
                }.font(.subheadline)
                Section { Button(t("reset"), role: .destructive) { draft = original; cover = nil; removeCover = false } }
            }.scrollContentBackground(.hidden).background { MusicBackground() }
                .navigationTitle(t("edit")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await save() } } label: { if saving { ProgressView() } else { Text(t("save")).bold() } }.disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .disabled(saving).interactiveDismissDisabled(saving)
                .sheet(isPresented: $picker) {
                    DocumentPicker(multiple: false) { urls in
                        picker = false
                        guard let url = urls.first else { return }
                        let kind = pickerKind
                        Task {
                            do {
                                let value = try await Task.detached(priority: .userInitiated) { () -> Data in
                                    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                                    if kind == "lyrics" { return Data(try FileStore.readText(url).utf8) }
                                    let data = try Data(contentsOf: url)
                                    guard data.count < 30_000_000 else { throw CocoaError(.fileReadTooLarge) }
                                    return data
                                }.value
                                if kind == "lyrics" { draft.lyrics = String(decoding: value, as: UTF8.self) }
                                else { try setCover(value) }
                            } catch { self.error = error.localizedDescription }
                        }
                    }.ignoresSafeArea()
                }
                .onChange(of: photo) { _, item in
                    Task { do { if let data = try await item?.loadTransferable(type: Data.self) { try setCover(data) } } catch { self.error = error.localizedDescription } }
                }
                .alert(t("error"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(t("ok")) { error = nil } } message: { Text((error ?? "") + "\n\n" + t("tagHelp")) }
        }
    }
    var coverSection: some View {
        Section(t("cover")) {
            HStack(spacing: 22) {
                if let cover, let image = UIImage(data: cover) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 104, height: 104).clipShape(RoundedRectangle(cornerRadius: 20))
                } else { Artwork(track: removeCover ? nil : draft, size: 104, radius: 20) }
                VStack(alignment: .leading, spacing: 15) {
                    PhotosPicker(selection: $photo, matching: .images) { Label(t("chooseCover"), systemImage: "photo") }
                    Button { pickerKind = "cover"; picker = true } label: { Label(t("file"), systemImage: "folder") }
                    Button(t("removeCover"), role: .destructive) { cover = nil; removeCover = true }
                }.font(.subheadline)
            }.padding(.vertical, 8)
        }
    }
    func field(_ key: String, _ path: WritableKeyPath<Track, String>, number: Bool = false) -> some View {
        LabeledContent(t(key)) {
            TextField(t(key), text: Binding(get: { draft[keyPath: path] }, set: { draft[keyPath: path] = $0 })).multilineTextAlignment(.trailing).keyboardType(number ? .numberPad : .default)
        }
    }
    func setCover(_ data: Data) throws {
        guard let image = UIImage(data: data) else { throw NSError(domain: "Artwork", code: 1, userInfo: [NSLocalizedDescriptionKey: t("artworkError")]) }
        let scale = min(1, 1500 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        cover = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.92)
        removeCover = false
    }
    func save() async {
        saving = true; defer { saving = false }
        do {
            draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            try await library.saveEdit(draft, cover: cover, removeCover: removeCover, writeTags: writeTags)
            UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
