import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel = "cover"
    @State private var editing: Track?
    @State private var scrubbing = false
    @State private var scrubTime = 0.0
    @State private var followLyrics = true
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 23) {
                        if let track = library.current {
                            if panel == "lyrics" { lyrics(track).frame(minHeight: max(220, geometry.size.height * 0.43)) }
                            else if panel == "queue" { queue.frame(minHeight: max(220, geometry.size.height * 0.43)) }
                            else {
                                Artwork(track: track, size: min(geometry.size.width - 64, geometry.size.height * 0.43), radius: 30)
                                    .shadow(color: .indigo.opacity(0.22), radius: 35, y: 20)
                                    .scaleEffect(library.playing || reduceMotion ? 1 : 0.92)
                                    .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.75), value: library.playing)
                                    .padding(.vertical, 12)
                            }
                            HStack(alignment: .center, spacing: 20) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(track.title).font(.title2.bold()).lineLimit(2)
                                    Text(track.artist.isEmpty ? t("unknownArtist") : track.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                                    Text(track.filename.components(separatedBy: ".").last?.uppercased() ?? "AUDIO").font(.system(size: 9, weight: .bold)).tracking(1.6).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button { library.favorite(track.id) } label: { Image(systemName: track.favorite ? "star.fill" : "star").font(.title3).frame(width: 40, height: 40) }.buttonStyle(.glass).accessibilityLabel(t(track.favorite ? "unfavorite" : "favorite"))
                                Menu {
                                    Button { editing = track } label: { Label(t("edit"), systemImage: "slider.horizontal.3") }
                                    ShareLink(item: library.url(track)) { Label(t("share"), systemImage: "square.and.arrow.up") }
                                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 40) }.accessibilityLabel(t("details")).accessibilityIdentifier("playerDetailsMenu")
                            }
                            timeline
                            controls
                            HStack(spacing: 15) { Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary); SystemVolume().frame(height: 28); Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary) }.accessibilityLabel(t("volume"))
                            bottomControls
                        } else { ContentUnavailableView(t("emptyTitle"), systemImage: "music.note") }
                    }.padding(.horizontal, 30).padding(.top, 8).padding(.bottom, 24).frame(minHeight: geometry.size.height, alignment: .top)
                }.scrollIndicators(.hidden)
            }
            .background { MusicBackground() }
            .navigationTitle(t("nowPlaying")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel(t("close")) }
                ToolbarItem(placement: .topBarTrailing) { sleepMenu }
            }
            .sheet(item: $editing) { TagEditor(track: $0) }
        }
        .alert(t("error"), isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button(t("ok")) { library.error = nil } } message: { Text(library.error ?? "") }
    }
    var timeline: some View {
        VStack(spacing: 3) {
            Slider(value: Binding(get: { scrubbing ? scrubTime : library.position }, set: { scrubTime = $0 }), in: 0...max(1, library.duration)) { active in
                if active { scrubTime = library.position; scrubbing = true }
                else { library.seek(scrubTime); scrubbing = false }
            }.accessibilityLabel(t("duration"))
            HStack { Text(clock(scrubbing ? scrubTime : library.position)); Spacer(); Text("−" + clock(max(0, library.duration - (scrubbing ? scrubTime : library.position)))) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
    var controls: some View {
        HStack(spacing: 0) {
            Button { library.shuffle() } label: { Image(systemName: "shuffle").font(.title3).foregroundStyle(library.shuffled ? Color.accentColor : .secondary).frame(width: 45, height: 48) }.accessibilityLabel(t("shuffle")).accessibilityValue(library.shuffled ? t("shuffle") : t("sleepOff"))
            Spacer()
            Button { library.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 29)).frame(width: 48, height: 60) }.accessibilityLabel(t("play") + " −1")
            Spacer()
            Button { library.toggle() } label: { Image(systemName: library.playing ? "pause.fill" : "play.fill").font(.system(size: 35, weight: .semibold)).frame(width: 76, height: 76) }.buttonStyle(.glassProminent).accessibilityLabel(t(library.playing ? "pause" : "play"))
            Spacer()
            Button { library.next() } label: { Image(systemName: "forward.fill").font(.system(size: 29)).frame(width: 48, height: 60) }.accessibilityLabel(t("playNext"))
            Spacer()
            Button { library.repeatMode = (library.repeatMode + 1) % 3 } label: { Image(systemName: library.repeatMode == 2 ? "repeat.1" : "repeat").font(.title3).foregroundStyle(library.repeatMode == 0 ? Color.secondary : Color.accentColor).frame(width: 45, height: 48) }.accessibilityLabel(t(["repeatOff", "repeatAll", "repeatOne"][library.repeatMode]))
        }.buttonStyle(.plain)
    }
    var bottomControls: some View {
        HStack {
            Button { withAnimation(.snappy) { panel = panel == "lyrics" ? "cover" : "lyrics" } } label: { Image(systemName: "quote.bubble").frame(width: 45, height: 42).foregroundStyle(panel == "lyrics" ? Color.accentColor : .primary) }.buttonStyle(.glass).accessibilityLabel(t("lyricsInfo"))
            Spacer()
            AirPlayButton().frame(width: 50, height: 44).accessibilityLabel(t("airplay"))
            Spacer()
            Button { withAnimation(.snappy) { panel = panel == "queue" ? "cover" : "queue" } } label: { Image(systemName: "list.bullet").frame(width: 45, height: 42).foregroundStyle(panel == "queue" ? Color.accentColor : .primary) }.buttonStyle(.glass).accessibilityLabel(t("queue"))
        }
    }
    var sleepMenu: some View {
        Menu {
            Button(t("sleepOff")) { library.sleepDate = nil }
            ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in Button(String(format: t("minutes"), minutes)) { library.sleepDate = Date().addingTimeInterval(Double(minutes) * 60) } }
        } label: { Image(systemName: library.sleepDate == nil ? "moon.zzz" : "moon.zzz.fill").foregroundStyle(library.sleepDate == nil ? Color.primary : Color.accentColor) }.accessibilityLabel(t("sleep"))
    }
    var queue: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("queue")).font(.largeTitle.bold())
            if library.upcoming.isEmpty { Text(t("queueEmpty")).foregroundStyle(.secondary).padding(.top, 30) }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(library.upcoming) { track in
                        HStack {
                            Button { library.play(track) } label: { TrackRow(track: track) }.buttonStyle(.plain)
                            Button { library.removeUpcoming(track.id) } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary).frame(width: 36, height: 44) }.accessibilityLabel(t("removeQueue"))
                        }
                    }
                }
            }.frame(maxHeight: 300)
        }
    }
    @ViewBuilder func lyrics(_ track: Track) -> some View {
        let lines = Lyrics.parse(track.lyrics)
        if track.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "quote.bubble").font(.system(size: 40)).foregroundStyle(.tint)
                Text(t("lyricsEmpty")).font(.title2.bold())
                Text(t("lyricsEmptyBody")).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button(t("edit")) { editing = track }.buttonStyle(.glass)
            }
        } else if lines.isEmpty {
            ScrollView { Text(track.lyrics).font(.system(size: 27, weight: .bold, design: .rounded)).lineSpacing(10).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.vertical, 20) }.frame(maxHeight: 360)
        } else {
            let active = Lyrics.active(lines, at: library.position)
            VStack(spacing: 6) {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(lines) { line in
                                Button { library.seek(line.time); followLyrics = true } label: {
                                    Text(line.text.isEmpty ? "♪" : line.text).font(.system(size: 29, weight: .bold, design: .rounded)).multilineTextAlignment(.leading).foregroundStyle(active == line.id ? Color.primary : Color.secondary.opacity(0.45)).frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain).id(line.id)
                            }
                        }.padding(.vertical, 90)
                    }.frame(maxHeight: 350).simultaneousGesture(DragGesture().onChanged { _ in followLyrics = false })
                        .onChange(of: active) { _, value in if followLyrics, let value { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { reader.scrollTo(value, anchor: .center) } } }
                        .onAppear { if let active { reader.scrollTo(active, anchor: .center) } }
                }
                if !followLyrics { Button(t("syncedLyrics")) { followLyrics = true }.font(.caption).buttonStyle(.glass) }
            }
        }
    }
}
