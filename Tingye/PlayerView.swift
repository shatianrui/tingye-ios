import SwiftUI
import AVFoundation

/// 刊版听书页：上半是封面色块刊头（书名大字），下半是纸上的句子流——当前句用荧光笔划出；
/// 底部 1.5pt 墨线之下是句序号、墨色方钮与四个常用工具。设计稿：Figma「06 播放器 Player」。
struct PlayerView: View {
    @ScaledMetric(relativeTo: .body) private var uiScale: CGFloat = 1
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject var player: SpeechPlayer
    /// 从阅读页打开时，「看原文」只需收起；从迷你播放器打开时要翻开这本书。
    var fromReader = false
    @State private var settings = false
    @State private var chaptersSheet = false
    @State private var endingListening = false

    private var content: Color { Theme.ink }
    private var secondary: Color { Theme.ink2 }
    private var tertiary: Color { Theme.ink3 }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            if let book = player.book {
                VStack(spacing: 0) {
                    hero(book)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            sentenceStream
                            if let error = player.error { errorNotice(error) }
                        }
                        .padding(.horizontal, Theme.inset)
                        .padding(.top, 22)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 600, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    controls
                }
            } else { emptyState }
        }
        .foregroundStyle(content)
        .tint(Theme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("结束这次听书？", isPresented: $endingListening, titleVisibility: .visible) {
            Button("结束听书", role: .destructive) { player.stop(); model.showingPlayer = false; dismiss() }
            Button("取消", role: .cancel) {}
        } message: { Text("阅读进度会保留，随时可以继续。") }
        .sheet(isPresented: $settings) {
            NavigationStack { VoiceSettingsView() }.environmentObject(model).tint(Theme.accent)
        }
        .sheet(isPresented: $chaptersSheet) {
            if let book = player.book {
                NavigationStack { ChapterListView(book: book, player: player).environmentObject(model) }
                    .tint(Theme.accent)
                    .presentationDetents([.medium, .large])
            }
        }
        #if DEBUG
        .task {
            switch UIReview.screen {
            case "player-voice": settings = true
            case "player-chapters": chaptersSheet = true
            default: break
            }
        }
        #endif
    }

    // MARK: 封面色块刊头

    private func hero(_ book: Book) -> some View {
        let fg = model.covers[book.id] == nil ? Theme.coverForeground(book.color) : Color.white
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    ThemeIcon(symbol: Icon.collapse, size: 24, weight: .semibold)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("收起播放器")
                Text("正在听 · 第 \(player.chapter + 1) / \(max(1, player.chapterCount)) 章")
                    .font(Theme.kicker).tracking(1.4).monospacedDigit()
                    .frame(maxWidth: .infinity)
                // 回到正文是听书时最常用的跳转，单独放在顶栏
                Button {
                    if fromReader { dismiss() }
                    else { dismiss(); model.showingPlayer = false; model.selectedBook = book }
                } label: {
                    ThemeIcon(symbol: Icon.read, size: 24)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("看原文")
                .accessibilityIdentifier("player.backToReader")
                // 低频操作：声音配置、跳章、结束
            Menu {
                    Button { settings = true } label: { Label("声音设置", systemImage: Icon.speaker) }
                        .accessibilityLabel("声音设置，当前 \(player.voiceLabel)")
                        .accessibilityIdentifier("player.voice")
                    Section("章节") {
                        Button { player.skipChapter(-1) } label: { Label("上一章", systemImage: Icon.previousChapter) }
                            .disabled(player.chapter == 0)
                        Button { player.skipChapter(1) } label: { Label("下一章", systemImage: Icon.nextChapter) }
                            .disabled(player.chapter + 1 >= player.chapterCount)
                    }
                    Button(role: .destructive) { endingListening = true } label: { Label("结束听书", systemImage: Icon.stopListening) }
                } label: {
                    ThemeIcon(symbol: Icon.more, size: 24)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("更多听书操作")
                .accessibilityIdentifier("player.more")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -10)
            HStack(alignment: .bottom, spacing: 16) {
                BookCoverView(title: book.title, color: book.color, image: model.covers[book.id], width: 84)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(fg.opacity(0.35), lineWidth: 1))
                    .scaleEffect(player.playing ? 1 : 0.94, anchor: .bottomLeading)
                    .animation(Theme.smoothSpring, value: player.playing)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(Theme.serifBold(40, relativeTo: .largeTitle))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text([book.author, player.chapterTitle].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 14 * uiScale))
                        .opacity(0.85)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, Theme.inset)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            CoverBackdrop(color: book.color, image: model.covers[book.id])
                .ignoresSafeArea(edges: .top)
                .animation(.easeInOut(duration: 0.5), value: book.id)
        }
    }

    // MARK: 句子流：上两句（灰）/ 当前句（荧光笔）/ 后三句（渐淡）；轻点任一句跳过去

    private var sentenceStream: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                if player.playing && !player.buffering {
                    Image(systemName: Icon.listening).symbolEffect(.variableColor.iterative, isActive: true)
                }
                Text(player.buffering ? "正在准备声音" : (player.playing ? "正在朗读" : "朗读已暂停"))
            }
            .font(Theme.kicker).tracking(1.2).foregroundStyle(Theme.accent)
            ForEach([2, 1], id: \.self) { back in
                if player.position - back >= 0, let previous = player.surroundingSentence(before: player.position - back + 1) {
                    lyricLine(previous.text, offset: -back, opacity: back == 2 ? 0.55 : 1)
                }
            }
            if let sentence = player.currentSentence {
                Text(sentence.text)
                    .font(Theme.serifBold(25, relativeTo: .title2)).lineSpacing(9)
                    .fixedSize(horizontal: false, vertical: true)
                    .markerHighlight()
                    .id(player.position)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    .accessibilityLabel("当前句：\(sentence.text)")
            } else {
                Text(player.book?.chapters.first?.text ?? "暂无内容")
                    .font(Theme.serif(19, relativeTo: .title3)).lineSpacing(6).lineLimit(4)
            }
            ForEach([1, 2, 3], id: \.self) { ahead in
                if let next = player.surroundingSentence(after: player.position + ahead - 1) {
                    lyricLine(next.text, offset: ahead, opacity: [1, 0.7, 0.45][ahead - 1])
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .animation(.easeOut(duration: 0.3), value: player.position)
    }

    private func lyricLine(_ text: String, offset: Int, opacity: Double) -> some View {
        Button { Haptics.light(); player.skip(offset) } label: {
            Text(text)
                .font(Theme.serif(17, relativeTo: .body)).lineSpacing(5)
                .foregroundStyle(Theme.ink3.opacity(opacity))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(offset < 0 ? "跳到上一句：\(text)" : "跳到下一句：\(text)")
    }

    // MARK: 控制区：句序号、墨色方钮、四个工具

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text(String(format: "%02d", player.position + 1)).font(Theme.display(26)).monospacedDigit()
                ProgressBar(value: player.progress, height: 4)
                    .accessibilityLabel("本章朗读进度")
                    .accessibilityValue("\(Int(player.progress * 100))%，第 \(player.position + 1) 句，共 \(max(1, player.count)) 句")
                Text(String(format: "%02d", max(1, player.count))).font(Theme.display(26)).monospacedDigit().foregroundStyle(tertiary)
            }
            transportRow
            footer
        }
        .padding(.horizontal, Theme.inset).padding(.top, 14).padding(.bottom, 10)
        .frame(maxWidth: 600).frame(maxWidth: .infinity)
        .background(Theme.bg.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { InkRule(height: 1.5) }
    }

    private var transportRow: some View {
        HStack(spacing: 20) {
            TransportButton(systemName: Icon.previousSentence, label: "上一句", size: 64) { player.skip(-1) }
                .accessibilityIdentifier("player.previousSentence")
            Spacer(minLength: 0)
            Button { Haptics.light(); player.toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.ink)
                    if player.buffering { ProgressView().tint(Theme.onInk) }
                    else { ThemeIcon(symbol: Icon.playback(player.playing), size: 32).foregroundStyle(Theme.onInk) }
                }
                .frame(width: 76, height: 76)
            }
            .buttonStyle(PressButtonStyle(scale: 0.94))
            .accessibilityLabel(player.buffering ? "正在准备声音" : (player.playing ? "暂停朗读" : "继续朗读"))
            .accessibilityIdentifier("player.toggle")
            Spacer(minLength: 0)
            TransportButton(systemName: Icon.nextSentence, label: "下一句", size: 64) { player.skip(1) }
                .accessibilityIdentifier("player.nextSentence")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 78)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { chaptersSheet = true } label: { footerItem(Icon.contents, "章节") }
                .accessibilityLabel("听书目录，第 \(player.chapter + 1) 章")
                .accessibilityIdentifier("player.contents")
            Menu {
                ForEach([0, 15, 30, 45, 60], id: \.self) { minutes in
                    Button(minutes == 0 ? "关闭定时" : "\(minutes) 分钟后停止") { player.setSleep(minutes: minutes) }
                }
            } label: { footerItem(Icon.sleepTimer, sleepLabel, highlighted: player.sleepUntil != nil) }
            .accessibilityLabel(player.sleepUntil == nil ? "设置定时停止" : sleepLabel)
            .accessibilityIdentifier("player.sleep")
            Menu {
                Picker("语速", selection: Binding(get: { player.rate }, set: { player.changeRate($0) })) {
                    ForEach([0.5, 0.75, 0.8, 1.0, 1.2, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                        Text(value.rateText + "×").tag(value)
                    }
                }
            } label: { footerItem(Icon.rate, "\(player.rate.rateText)×", highlighted: player.rate != 1.0) }
            .accessibilityLabel("语速，当前 \(player.rate.rateText) 倍")
            .accessibilityIdentifier("player.rate")
            VStack(spacing: 0) {
                AirPlayButton().frame(width: 44, height: 40)
                Text("AirPlay").font(Theme.sans(11 * uiScale, weight: .medium)).foregroundStyle(secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .top)
            .accessibilityElement(children: .contain)
        }
        .buttonStyle(.plain)
    }

    private func footerItem(_ icon: String, _ title: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 0) {
            ThemeIcon(symbol: icon, size: 24).frame(height: 40)
                .foregroundStyle(highlighted ? Theme.accent : content)
            Text(title).font(Theme.sans(11 * uiScale, weight: .medium)).foregroundStyle(highlighted ? Theme.accent : secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .top).contentShape(Rectangle())
    }

    private func errorNotice(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(error).font(.footnote).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(player.timingLabel).font(.caption).foregroundStyle(tertiary)
                Spacer()
                Button("重试朗读") { player.resume() }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
        }
        .padding(.leading, 14).padding(.vertical, 6)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.danger).frame(width: 3) }
    }

    private var sleepLabel: String {
        if let until = player.sleepUntil, until.timeIntervalSinceNow > 0 {
            return "\(Int(ceil(until.timeIntervalSinceNow / 60))) 分后停"
        }
        return "定时"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("听一卷书，歇一歇眼", systemImage: Icon.listen)
        } description: { Text("打开一本书，轻点耳机，继续书中的旅程。") } actions: {
            if let last = model.lastBook {
                Button("听《\(last.title)》") { model.listen(last.id) }
                    .buttonStyle(PrimaryButtonStyle(height: 44)).frame(maxWidth: 240)
            }
        }
        .foregroundStyle(content)
    }
}

// MARK: - 子组件

private struct TransportButton: View {
    let systemName: String
    let label: String
    let size: CGFloat
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button { action(); Haptics.light() } label: {
            ThemeIcon(symbol: systemName, size: 30)
                .foregroundStyle(enabled ? Theme.ink : Theme.ink3)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(PressButtonStyle(scale: 0.94))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// 章节滑杆：拖动结束后跳转章节
private struct ChapterProgressSlider: View {
    @ObservedObject var player: SpeechPlayer
    @State private var dragging = false
    @State private var value: Double = 0
    var body: some View {
        Slider(
            value: Binding(
                get: { dragging ? value : Double(player.chapter) },
                set: { value = $0 }
            ),
            in: 0...max(1, Double(player.chapterCount - 1)),
            step: 1
        ) { editing in
            if editing {
                value = Double(player.chapter)
                dragging = true
            } else {
                dragging = false
                let target = max(0, min(player.chapterCount - 1, Int(value.rounded())))
                player.seek(chapter: target, position: 0)
            }
        }
        .tint(Theme.accent)
        .disabled(player.chapterCount <= 1)
        .accessibilityLabel("章节进度")
        .accessibilityValue("第 \(player.chapter + 1) 章，共 \(max(1, player.chapterCount)) 章")
    }
}

// MARK: - 章节列表（原生 List）

struct ChapterListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let book: Book
    @ObservedObject var player: SpeechPlayer
    @State private var query = ""
    private var filtered: [(index: Int, chapter: Chapter)] {
        book.chapters.enumerated()
            .filter { query.isEmpty || $0.element.title.localizedCaseInsensitiveContains(query) }
            .map { (index: $0.offset, chapter: $0.element) }
    }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title).font(Theme.serifSemibold(24, relativeTo: .title2)).foregroundStyle(Theme.ink)
                    HStack(spacing: 7) {
                        Image(systemName: Icon.listening)
                        Text("共 \(book.chapters.count) 章 · 正在听第 \(player.chapter + 1) 章")
                    }
                    .font(.caption).foregroundStyle(Theme.accent)
                    Text("\(player.timingLabel) · \(player.rate.rateText)×")
                        .font(.caption).foregroundStyle(Theme.ink3)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 0))
                VStack(spacing: 8) {
                    HStack {
                        Button { player.skipChapter(-1) } label: { Label("上一章", systemImage: Icon.back) }
                            .disabled(player.chapter == 0)
                        Spacer()
                        Button { player.skipChapter(1) } label: { Label("下一章", systemImage: Icon.disclosure) }
                            .disabled(player.chapter + 1 >= player.chapterCount)
                    }
                    .font(.subheadline).buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    ChapterProgressSlider(player: player)
                }
                .listRowBackground(Theme.surface)
                ForEach(filtered, id: \.index) { item in
                    let current = item.index == player.chapter
                    Button {
                        player.seek(chapter: item.index, position: 0)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Text(String(format: "%02d", item.index + 1))
                                .font(.system(size: 12, weight: current ? .semibold : .regular).monospacedDigit())
                                .foregroundStyle(current ? Theme.accent : Theme.ink3)
                                .frame(width: 30, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.chapter.title)
                                    .font(Theme.serif(16).weight(current ? .medium : .regular))
                                    .foregroundStyle(current ? Theme.ink : Theme.ink2)
                                if current {
                                    Text("正在听 · \(Int(player.progress * 100))%")
                                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if current {
                                Image(systemName: Icon.listening).font(.system(size: 17)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(current ? Theme.accentSoft : Theme.surface)
                    .id(item.index)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .searchable(text: $query, prompt: "搜索章节")
            .navigationTitle("听书目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: Icon.close)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("关闭章节列表")
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(player.chapter, anchor: .center)
                }
            }
        }
    }

}

// MARK: - 听书与声音设置面板（原生 Form）

struct VoiceSettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var fetchedVoices: [CloudVoice] = []
    @State private var notice = ""
    typealias CloudVoice = CloudSpeech.Voice
    @Environment(\.dismiss) var dismiss
    @State private var provider = UserDefaults.standard.string(forKey: "voice.provider") ?? "system"
    @State private var rate = Double(VoiceOptions.load().rate)
    @State private var groupID = UserDefaults.standard.string(forKey: "voice.groupID") ?? ""
    @State private var azureRegion = UserDefaults.standard.string(forKey: "voice.azureRegion") ?? ""
    @State private var roles = UserDefaults.standard.bool(forKey: "voice.roles")
    @State private var maleVoice = ""
    @State private var femaleVoice = ""
    @State private var voice = ""
    @State private var modelName = ""
    @State private var apiKey = ""
    @State private var error: String?
    @State private var preview: AVAudioPlayer?
    @State private var systemPreview = AVSpeechSynthesizer()
    @State private var previewTask: Task<Void, Never>?
    @State private var previewing = false
    @State private var pausedBookForPreview = false
    @State private var previewRevision = UUID()
    /// 各服务商未保存的修改：切换朗读方式时先存草稿，保存时一并写入，互不覆盖。
    @State private var drafts: [String: Draft] = [:]
    @State private var loadedProvider = ""
    private struct Draft { var voice: String; var model: String; var key: String; var male: String; var female: String }
    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") || $0.language.hasPrefix("en") }.sorted { $0.language + $0.name < $1.language + $1.name }
    }

    var body: some View {
        Form {
            providerSection.listRowBackground(Theme.surface)
            connectionSection.listRowBackground(Theme.surface)
            voiceSection.listRowBackground(Theme.surface)
            rateSection.listRowBackground(Theme.surface)
            roleSection.listRowBackground(Theme.surface)
            Section {
                Text(auditionHint)
                    .font(.caption).foregroundStyle(Theme.ink2)
                if let error { Text(error).font(.caption).foregroundStyle(Theme.danger) }
                if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(Theme.ink2) }
            } header: { Text("3 · 试听与保存") }
        }
        .scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
        .navigationTitle("声音设置")
            .navigationBarBackButtonHidden().navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.accessibilityLabel("取消声音设置，不保存修改")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { previewing ? stopPreview() : testVoice() } label: {
                    Label(previewing ? "停止试听" : "试听", systemImage: Icon.previewPlayback(previewing))
                }
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .accessibilityIdentifier("voice.preview")
                Button("保存并应用") { save() }
                    .buttonStyle(PrimaryButtonStyle(height: 48))
                    .accessibilityIdentifier("voice.save")
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
            .background(Theme.bg)
        }
        .onAppear { if loadedProvider.isEmpty { load(provider) } }
        .onDisappear { stopPreview() }
    }

    private var providerSection: some View {
        Section {
            Picker("提供方", selection: $provider) {
                Text("系统声音 · 离线").tag("system")
                Text("智谱 GLM").tag("glm")
                Text("MiniMax").tag("minimax")
                Text("Microsoft Azure").tag("azure")
                Text("ElevenLabs").tag("elevenlabs")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("voice.provider")
            .onChange(of: provider) { old, new in
                stopPreview()
                drafts[old] = Draft(voice: voice, model: modelName, key: apiKey, male: maleVoice, female: femaleVoice)
                fetchedVoices = []; notice = ""; error = nil
                load(new)
            }
        } header: { Text("1 · 选择提供方") } footer: { Text(providerNote) }
    }

    @ViewBuilder private var connectionSection: some View {
        if provider != "system" {
            Section {
                SecureField(provider == "azure" ? "Speech Key（必填）" : "API Key（必填）", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if provider == "azure" {
                    TextField("区域，例如 eastasia", text: $azureRegion).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if provider == "minimax" {
                    TextField("Group ID（选填）", text: $groupID).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if provider != "azure" {
                    Picker("模型", selection: $modelName) {
                        ForEach(presetModels, id: \.self) { Text($0).tag($0) }
                        if !presetModels.contains(modelName) { Text(modelName).tag(modelName) }
                    }
                    DisclosureGroup("自定义模型") {
                        TextField("模型 ID", text: $modelName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
            } header: { Text("连接 \(VoiceOptions.providerName(provider))") } footer: { Text(cloudNote) }
        }
    }

    private var voiceSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: Icon.voice).font(.system(size: 21)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Theme.auroraGradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentVoiceName).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(currentVoiceSubtitle).font(.caption2).foregroundStyle(Theme.ink3)
                }
            }
            voicePicker
            if provider == "minimax" || provider == "elevenlabs" {
                Button { refreshVoices() } label: { Label("刷新账号音色", systemImage: Icon.refresh) }
                    .disabled(app.busy || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: { Text("2 · 选择音色") }
    }

    private var rateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("语速").font(.subheadline)
                    Spacer()
                    Text(rate.rateText + "×").font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(Theme.accent)
                }
                Slider(value: $rate, in: 0.5...2, step: 0.05)
                    .accessibilityLabel("试听与朗读语速").accessibilityValue(rate.rateText + "倍")
            }
        } header: { Text("朗读节奏") } footer: { Text("试听使用当前语速，保存后应用到听书。") }
    }

    private var roleSection: some View {
        Section {
            DisclosureGroup("分角色配音") {
                Toggle("启用分角色配音", isOn: $roles)
                if roles {
                    Picker("男声", selection: $maleVoice) {
                        Text("与旁白相同").tag("")
                        ForEach(voiceChoices, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Picker("女声", selection: $femaleVoice) {
                        Text("与旁白相同").tag("")
                        ForEach(voiceChoices, id: \.value) { Text($0.label).tag($0.value) }
                    }
                }
                Text("中文小说中的男女对话使用对应音色；无法判断时使用旁白。此功能仍在测试中。")
                    .font(.caption).foregroundStyle(Theme.ink3)
            }
        } header: { Text("更多声音选项") }
    }

    // MARK: - Voice Picker

    @ViewBuilder
    private var voicePicker: some View {
        if provider == "system" {
            Picker("系统声音", selection: $voice) {
                Text("默认中文声音").tag("")
                ForEach(voices, id: \.identifier) { v in
                    Text("\(v.name) · \(v.language)").tag(v.identifier)
                }
            }
        } else if provider == "glm" {
            Picker("音色", selection: $voice) {
                ForEach([("tongtong", "彤彤"), ("chuichui", "锤锤"), ("xiaochen", "小陈"), ("jam", "动动"), ("kazi", "卡子"), ("douji", "豆吉"), ("luodo", "洛多")], id: \.0) { key, title in
                    Text(title).tag(key)
                }
            }
        } else if provider == "azure" {
            Picker("音色", selection: $voice) {
                ForEach(AzureVoices.all, id: \.value) { v in Text(v.label).tag(v.value) }
                if !AzureVoices.all.contains(where: { $0.value == voice }) { Text(voice).tag(voice) }
            }
        } else if provider == "elevenlabs" {
            Picker("音色", selection: $voice) {
                ForEach(elevenVoices, id: \.value) { v in Text(v.label).tag(v.value) }
                if !elevenVoices.contains(where: { $0.value == voice }) { Text("自定义音色").tag(voice) }
            }
            TextField("音色 ID（可从 ElevenLabs 音色库复制）", text: $voice)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            Picker("预设音色", selection: $voice) {
                ForEach(minimaxVoices, id: \.value) { v in Text(v.label).tag(v.value) }
                if !minimaxVoices.contains(where: { $0.value == voice }) { Text("自定义音色").tag(voice) }
            }
        }
    }

    private var minimaxVoices: [CloudVoice] {
        if !fetchedVoices.isEmpty { return fetchedVoices }
        return zip(["male-qn-qingse", "female-shaonv", "female-yujie", "female-chengshu", "female-tianmei", "presenter_male", "presenter_female", "audiobook_male_1", "audiobook_male_2", "audiobook_female_1", "audiobook_female_2", "male-qn-jingying", "male-qn-badao", "male-qn-daxuesheng", "female-qn-qingse", "female-qn-yujie", "female-qn-chengshu", "female-qn-tianmei"], ["青涩青年", "少女", "御姐", "成熟女性", "甜美女性", "男性主持人", "女性主持人", "有声书男声 1", "有声书男声 2", "有声书女声 1", "有声书女声 2", "精英青年", "霸道青年", "大学生", "青涩女声", "御姐女声", "成熟女声", "甜美女声"]).map { CloudVoice(value: $0.0, label: $0.1) }
    }

    private var providerNote: String {
        switch provider {
        case "system": return "使用设备自带声音，无需联网、免费。可在系统设置 → 辅助功能 → 朗读内容 → 声音中下载更多声音。"
        case "azure": return "使用你自己的 Azure 语音资源（Speech Key + 区域），提供大量中文神经网络音色，有免费额度。"
        case "elevenlabs": return "使用你自己的 ElevenLabs API Key，多语言音色自然，带逐字时间戳。"
        default: return "使用你自己的 API Key 直连服务商，音质更自然，按服务商计费。"
        }
    }
    private var cloudNote: String {
        let privacy = "密钥只保存在本机钥匙串；朗读时会把当前句子发送给服务商合成语音。"
        switch provider {
        case "minimax": return "支持 MiniMax 国内版按量付费与 Token Plan（sk-cp- 开头）密钥，自动连接 api.minimax.cn。追求低延迟可选 speech-2.8-turbo。" + privacy
        case "azure": return "区域必须与 Azure 语音资源所在区域一致（在 Azure 门户的「密钥和终结点」中查看）。" + privacy
        case "elevenlabs": return "Flash 与 Turbo 模型延迟更低，Multilingual 适合长篇听书。" + privacy
        default: return "不经过听页服务器。" + privacy
        }
    }
    private var presetModels: [String] {
        switch provider {
        case "glm": return ["glm-tts"]
        case "elevenlabs": return ["eleven_multilingual_v2", "eleven_turbo_v2_5", "eleven_flash_v2_5", "eleven_v3"]
        default: return ["speech-2.8-hd", "speech-2.8-turbo", "speech-2.6-hd", "speech-2.6-turbo", "speech-02-hd", "speech-02-turbo", "speech-01-hd", "speech-01-turbo", "t2a-01-hd", "t2a-01"]
        }
    }
    private var elevenVoices: [CloudVoice] {
        if !fetchedVoices.isEmpty { return fetchedVoices }
        return [CloudVoice(value: "21m00Tcm4TlvDq8ikWAM", label: "Rachel"), CloudVoice(value: "pNInz6obpgDQGcFmaJgB", label: "Adam"),
                CloudVoice(value: "EXAVITQu4vr4xnSDxMaL", label: "Sarah"), CloudVoice(value: "onwK4e9ZLuTAKqWW03F9", label: "Daniel")]
    }
    /// 当前朗读方式下可选的全部音色（分角色用）
    private var voiceChoices: [CloudVoice] {
        switch provider {
        case "system": return voices.map { CloudVoice(value: $0.identifier, label: "\($0.name) · \($0.language)") }
        case "glm": return [("tongtong", "彤彤"), ("chuichui", "锤锤"), ("xiaochen", "小陈"), ("jam", "动动"), ("kazi", "卡子"), ("douji", "豆吉"), ("luodo", "洛多")].map { CloudVoice(value: $0.0, label: $0.1) }
        case "azure": return AzureVoices.all
        case "elevenlabs": return elevenVoices
        default: return minimaxVoices
        }
    }

    private var currentVoiceName: String {
        if provider == "system" {
            if voice.isEmpty { return "默认中文声音" }
            return voices.first(where: { $0.identifier == voice })?.name ?? "默认中文声音"
        }
        if provider == "glm" {
            let map = ["tongtong": "彤彤", "chuichui": "锤锤", "xiaochen": "小陈", "jam": "动动", "kazi": "卡子", "douji": "豆吉", "luodo": "洛多"]
            return map[voice] ?? voice
        }
        if provider == "azure" { return AzureVoices.all.first { $0.value == voice }?.label ?? voice }
        if provider == "elevenlabs" { return elevenVoices.first { $0.value == voice }?.label ?? voice }
        return minimaxVoices.first(where: { $0.value == voice })?.label ?? voice
    }

    private var currentVoiceSubtitle: String {
        if provider == "system" {
            if voice.isEmpty { return "系统 · 离线" }
            return voices.first(where: { $0.identifier == voice })?.language ?? ""
        }
        return ["glm": "智谱 GLM · 云端", "minimax": "MiniMax · 云端", "azure": "Microsoft Azure · 云端", "elevenlabs": "ElevenLabs · 云端"][provider] ?? "云端"
    }

    private func refreshVoices() {
        let key = apiKey, group = groupID, target = provider
        app.run("正在刷新音色") {
            let voices = target == "elevenlabs" ? try await CloudSpeech.elevenLabsVoices(key: key) : try await CloudSpeech.minimaxVoices(key: key, groupID: group)
            if target == "elevenlabs" { for v in voices { UserDefaults.standard.set(v.label, forKey: "voice.label.elevenlabs." + v.value) } }
            guard provider == target else { return }
            fetchedVoices = voices; notice = "已加载 \(voices.count) 个音色。"
        }
    }

    private var auditionHint: String {
        if previewing { return pausedBookForPreview ? "正在试听，听书已暂停。" : "正在试听当前配置…" }
        if pausedBookForPreview { return "试听后听书保持暂停；返回听书页轻点「播放」即可继续。" }
        return "确认音色后，试听并保存。试听会暂停当前听书。"
    }

    private var configurationIssue: String? {
        if provider != "system" && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请先填写提供方密钥，或选择系统声音。" }
        if provider == "azure" && azureRegion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写 Azure 语音资源所在区域。" }
        return nil
    }

    private func stopPreview() {
        previewRevision = UUID(); previewTask?.cancel(); previewTask = nil
        preview?.stop(); preview = nil; systemPreview.stopSpeaking(at: .immediate); previewing = false
    }

    private func testVoice() {
        if let issue = configurationIssue { error = issue; return }
        stopPreview(); error = nil
        if app.player.playing { app.player.pause(); pausedBookForPreview = true }
        let chosen = VoiceOptions.sanitized(provider: provider, model: modelName, voice: voice)
        let config = (provider, chosen.model, chosen.voice, apiKey, provider == "azure" ? azureRegion : groupID)
        let speed = rate, revision = previewRevision
        previewing = true
        previewTask = Task { @MainActor in
            defer { if previewRevision == revision { previewing = false } }
            do {
                try SpeechAudioSession.activate()
                let sample = "你好，这是听页的试听。选一种声音，让阅读慢慢继续。"
                if config.0 == "system" {
                    let line = AVSpeechUtterance(string: sample)
                    line.voice = config.2.isEmpty ? AVSpeechSynthesisVoice(language: "zh-CN") : AVSpeechSynthesisVoice(identifier: config.2)
                    line.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed)))
                    systemPreview.speak(line)
                    try await Task.sleep(for: .milliseconds(300))
                    while systemPreview.isSpeaking { try await Task.sleep(for: .milliseconds(150)) }
                } else {
                    let result = try await CloudSpeech.synthesize(sample, provider: config.0, model: config.1, voice: config.2, key: config.3, groupID: config.4)
                    try Task.checkCancellation()
                    guard previewRevision == revision else { return }
                    let audio = try AVAudioPlayer(data: result.audio)
                    audio.enableRate = true; audio.rate = Float(speed); audio.prepareToPlay(); audio.play(); preview = audio
                    while audio.isPlaying { try await Task.sleep(for: .milliseconds(150)) }
                }
            } catch is CancellationError {} catch {
                if previewRevision == revision { self.error = error.localizedDescription }
            }
        }
    }

    /// 读取某个服务商自己的模型、音色与密钥（与播放器同一套键），有未保存的草稿时优先用草稿。
    private func load(_ target: String) {
        VoiceOptions.migrateLegacy()
        loadedProvider = target
        if let draft = drafts[target] { voice = draft.voice; modelName = draft.model; apiKey = draft.key; maleVoice = draft.male; femaleVoice = draft.female; return }
        let d = UserDefaults.standard
        let chosen = VoiceOptions.sanitized(provider: target, model: d.string(forKey: VoiceOptions.modelKey(target)), voice: d.string(forKey: VoiceOptions.voiceKey(target)))
        voice = chosen.voice; modelName = chosen.model
        apiKey = VoiceOptions.apiKey(target)
        maleVoice = d.string(forKey: VoiceOptions.roleKey("male", target)) ?? ""
        femaleVoice = d.string(forKey: VoiceOptions.roleKey("female", target)) ?? ""
    }

    /// 仅保存时提交草稿；切换提供方不会改变正在使用的配置。
    private func save() {
        if let issue = configurationIssue { error = issue; return }
        drafts[provider] = Draft(voice: voice, model: modelName, key: apiKey, male: maleVoice, female: femaleVoice)
        let d = UserDefaults.standard
        do {
            for (target, draft) in drafts where target != "system" {
                let key = draft.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { try Keychain.save(Data(key.utf8), key: VoiceOptions.secretKey(target)) }
            }
        } catch { self.error = "无法保存密钥：" + error.localizedDescription; return }
        for (target, draft) in drafts {
            let chosen = VoiceOptions.sanitized(provider: target, model: draft.model, voice: draft.voice)
            d.set(chosen.voice, forKey: VoiceOptions.voiceKey(target))
            if target != "system" { d.set(chosen.model, forKey: VoiceOptions.modelKey(target)) }
            d.set(draft.male, forKey: VoiceOptions.roleKey("male", target))
            d.set(draft.female, forKey: VoiceOptions.roleKey("female", target))
        }
        d.set(provider, forKey: "voice.provider"); d.set(rate, forKey: "voice.rate")
        d.set(groupID, forKey: "voice.groupID"); d.set(azureRegion, forKey: "voice.azureRegion"); d.set(roles, forKey: "voice.roles")
        if provider == "elevenlabs", let label = elevenVoices.first(where: { $0.value == voice })?.label { d.set(label, forKey: "voice.label.elevenlabs." + voice) }
        stopPreview(); app.player.applyOptions(); dismiss()
    }

}

extension Double {
    /// 语速文字，最多两位小数：%.2g 会把 1.75 写成「1.8」。
    var rateText: String { formatted(.number.precision(.fractionLength(0...2))) }
}
