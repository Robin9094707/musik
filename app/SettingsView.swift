import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("theme") private var theme = "system"
    @State private var icon = UIApplication.shared.alternateIconName ?? "Aurora"
    @State private var iconError: String?
    @State private var welcome = false
    let icons = ["Aurora", "Ember", "Glacier", "Obsidian"]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image("IconAurora").resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) { Text("Simplex Music Player").font(.headline); Text(t("localOnly")).font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5)
                }
                Section(t("appearance")) {
                    Picker(t("theme"), selection: $theme) { Text(t("system")).tag("system"); Text(t("light")).tag("light"); Text(t("dark")).tag("dark") }
                    Picker(t("language"), selection: $language) { Text(t("system")).tag("system"); Text("Deutsch").tag("de"); Text("English").tag("en") }
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 18) {
                        ForEach(icons, id: \.self) { name in
                            Button { setIcon(name) } label: {
                                VStack(spacing: 8) {
                                    Image("Icon" + name).resizable().scaledToFit().frame(width: 65, height: 65).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(icon == name ? Color.accentColor : .clear, lineWidth: 3)).padding(3)
                                    Text(name).font(.caption2.weight(.medium)).foregroundStyle(.primary)
                                    Image(systemName: icon == name ? "checkmark.circle.fill" : "circle").font(.caption).foregroundStyle(icon == name ? Color.accentColor : Color.secondary)
                                }
                            }.buttonStyle(.plain).accessibilityLabel(name).accessibilityAddTraits(icon == name ? .isSelected : [])
                        }
                    }.padding(.vertical, 10)
                } header: { Text(t("appIcon")) } footer: { Text(t("iconHint")) }
                Section {
                    NavigationLink(t("formats")) { InfoPage(title: t("formats"), symbol: "waveform", text: t("formatsBody")) }
                    NavigationLink(t("lyricsInfo")) { InfoPage(title: t("lyricsInfo"), symbol: "quote.bubble", text: t("lyricsHelp")) }
                    NavigationLink(t("tagInfo")) { InfoPage(title: t("tagInfo"), symbol: "slider.horizontal.3", text: t("tagHelp")) }
                    NavigationLink(t("localOnly")) { InfoPage(title: t("localOnly"), symbol: "iphone", text: t("privacyBody")) }
                }
                Section {
                    Button(t("replayWelcome")) { welcome = true }
                    NavigationLink(t("licenses")) { ScrollView { Text(acknowledgements).font(.caption.monospaced()).textSelection(.enabled).padding() }.navigationTitle(t("licenses")) }
                    LabeledContent(t("version"), value: "2.0.0")
                }
            }.scrollContentBackground(.hidden).background { MusicBackground() }.navigationTitle(t("settings"))
                .fullScreenCover(isPresented: $welcome) { WelcomeView { welcome = false } }
                .alert(t("error"), isPresented: Binding(get: { iconError != nil }, set: { if !$0 { iconError = nil } })) { Button(t("ok")) { iconError = nil } } message: { Text(iconError ?? "") }
        }
    }
    var acknowledgements: String {
        if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return "SFBAudioEngine — Stephen F. Booth — MIT\nhttps://github.com/sbooth/SFBAudioEngine\n\nTagLib and bundled audio codecs. See repository for full license notices."
    }
    func setIcon(_ name: String) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(name == "Aurora" ? nil : name) { error in
            Task { @MainActor in if let error { iconError = error.localizedDescription } else { icon = name; UISelectionFeedbackGenerator().selectionChanged() } }
        }
    }
}
struct InfoPage: View {
    let title: String
    let symbol: String
    let text: String
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) { Image(systemName: symbol).font(.system(size: 55, weight: .light)).foregroundStyle(.tint); Text(title).font(.largeTitle.bold()); Text(text).font(.body).foregroundStyle(.secondary).lineSpacing(6) }.padding(30).frame(maxWidth: .infinity, alignment: .leading) }.background { MusicBackground() }.navigationBarTitleDisplayMode(.inline)
    }
}
struct WelcomeView: View {
    let finish: () -> Void
    @State private var page = 0
    @AppStorage("appLanguage") private var language = "system"
    var body: some View {
        VStack(spacing: 20) {
            HStack { Spacer(); Menu { Button("Deutsch") { language = "de" }; Button("English") { language = "en" }; Button(t("system")) { language = "system" } } label: { Label(language == "system" ? t("system") : language == "de" ? "Deutsch" : "English", systemImage: "globe") }.font(.subheadline).buttonStyle(.glass) }.padding(.horizontal, 25)
            TabView(selection: $page) {
                welcomePage.tag(0)
                featurePage(symbol: "square.and.arrow.down.on.square", title: "onboard1", body: "onboard1Body", color: .cyan).tag(1)
                featurePage(symbol: "quote.bubble.fill", title: "onboard2", body: "onboard2Body", color: .purple).tag(2)
                featurePage(symbol: "sparkles", title: "onboard3", body: "onboard3Body", color: .indigo).tag(3)
            }.tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 8) { ForEach(0..<4) { i in Capsule().fill(i == page ? Color.accentColor : .secondary.opacity(0.2)).frame(width: i == page ? 24 : 7, height: 7) } }.animation(.snappy, value: page)
            Button { if page == 3 { finish() } else { withAnimation(.smooth) { page += 1 } } } label: { HStack { Text(t(page == 3 ? "start" : "continue")).font(.headline); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity).padding(.vertical, 14) }.buttonStyle(.glassProminent).padding(.horizontal, 28).padding(.bottom, 20)
        }.padding(.top, 18).background { MusicBackground() }.interactiveDismissDisabled()
    }
    var welcomePage: some View {
        VStack(spacing: 22) {
            Image("IconAurora").resizable().frame(width: 154, height: 154).clipShape(RoundedRectangle(cornerRadius: 39)).shadow(color: .indigo.opacity(0.25), radius: 40, y: 15)
            VStack(spacing: 8) { Text(t("welcome")).font(.title3).foregroundStyle(.secondary); Text("Simplex\nMusic Player").font(.system(size: 43, weight: .bold, design: .rounded)).tracking(-1.3).multilineTextAlignment(.center) }
            Text(t("welcomeBody")).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)
        }.padding(24)
    }
    func featurePage(symbol: String, title: String, body: String, color: Color) -> some View {
        VStack(spacing: 30) {
            ZStack { Circle().fill(color.opacity(0.12)).frame(width: 190, height: 190); Image(systemName: symbol).font(.system(size: 75, weight: .light)).foregroundStyle(color) }.glassEffect(.regular, in: .circle)
            Text(t(title)).font(.system(size: 32, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            Text(t(body)).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
        }.padding(34)
    }
}
