import SwiftUI
import AVFoundation

/// Voice configuration shared by the reader and app settings.
struct VoiceSettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var fetchedVoices: [CloudVoice] = []
    @State private var notice = ""
    typealias CloudVoice = CloudSpeech.Voice
    @Environment(\.dismiss) var dismiss
    @State private var provider = UserDefaults.standard.string(forKey: "voice.provider") ?? "system"
    @State private var rate = Double(VoiceOptions.load().rate)
    @State private var groupID = UserDefaults.standard.string(forKey: "voice.groupID") ?? ""
    @State private var customURL = UserDefaults.standard.string(forKey: VoiceOptions.customURLKey) ?? ""
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
            Section {
                voiceHero
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
            }
            .listRowBackground(Theme.accentSoft)
            Section {
                NavigationLink {
                    voiceDetail("选择音色") { voiceSection }
                } label: { voiceSettingLabel("音色", value: currentVoiceName) }
            }
            .listRowBackground(Theme.surface)
            Section {
                NavigationLink {
                    voiceDetail("朗读节奏") { rateSection }
                } label: { voiceSettingLabel("语速", value: rate.rateText + "×") }
            }
            .listRowBackground(Theme.surface)
            Section {
                NavigationLink {
                    voiceDetail("分角色配音") { roleSection }
                } label: { voiceSettingLabel("分角色配音", value: roles ? "Beta · 已开启" : "Beta · 关闭") }
            }
            .listRowBackground(Theme.surface)
            Section("中国区语音 API") {
                chinaVoiceLink("glm", title: "智谱 GLM · 中国区", subtitle: "glm-tts · 中文音色")
                chinaVoiceLink("minimax", title: "MiniMax · 中国区", subtitle: "Speech 2.8 · 支持账号音色")
            }
            .listRowBackground(Theme.surface)
            Section {
                NavigationLink { cloudConfiguration } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("连接云语音服务").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                        Text("GLM / MiniMax / Azure / ElevenLabs / 自定义")
                            .font(.caption).foregroundStyle(Theme.ink2)
                    }.padding(.vertical, 6)
                }
                .accessibilityIdentifier("voice.cloud")
            }
            .listRowBackground(Theme.surface)
            Section {
                HStack {
                    Text("音频输出").font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    AirPlayButton().frame(width: 44, height: 44)
                        .accessibilityLabel("选择音频输出设备")
                        .accessibilityIdentifier("voice.audioOutput")
                }
            }
            .listRowBackground(Theme.surface)
            if error != nil || !notice.isEmpty { voiceNotices }
        }
        .scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
        .navigationTitle("声音与朗读")
        .navigationBarBackButtonHidden().navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.accessibilityLabel("取消声音设置，不保存修改")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("保存并应用") { save() }
                .buttonStyle(PrimaryButtonStyle(height: 50))
                .accessibilityIdentifier("voice.save")
                .padding(.horizontal, Theme.inset).padding(.vertical, 12)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
                .background(Theme.bg)
        }
        .feedbackOverlay()
        .respectReducedMotion()
        .onAppear { if loadedProvider.isEmpty { load(provider) } }
        .onDisappear { stopPreview() }
    }

    private var voiceHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ThemeIcon(symbol: "waveform", size: 32).foregroundStyle(Theme.accent)
                Spacer()
                Text(provider == "system" ? "离线可用" : "云端合成")
                    .font(.caption).foregroundStyle(Theme.accent)
            }
            Text(VoiceOptions.providerName(provider)).scaledFont(20, weight: .bold, relativeTo: .title3)
                .foregroundStyle(Theme.ink)
            Text(provider == "system" ? "使用这台设备的声音，无需密钥。" : currentVoiceSubtitle)
                .font(.caption).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button { previewing ? stopPreview() : testVoice() } label: {
                Text(previewing ? "停止试听" : "试听当前声音")
            }
            .buttonStyle(SecondaryButtonStyle(height: 50))
            .accessibilityIdentifier("voice.preview")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func voiceSettingLabel(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(value).font(.caption).foregroundStyle(Theme.ink2)
                .lineLimit(2).multilineTextAlignment(.trailing)
        }.frame(minHeight: 36)
    }

    private func voiceDetail<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Form { content().listRowBackground(Theme.surface) }
            .scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
            .navigationTitle(title).navigationBarTitleDisplayMode(.large)
    }

    private func chinaVoiceLink(_ target: String, title: String, subtitle: String) -> some View {
        NavigationLink {
            cloudConfiguration.onAppear { provider = target }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.caption).foregroundStyle(Theme.ink2)
            }.padding(.vertical, 6)
        }
        .accessibilityIdentifier("voice.connect." + target)
    }

    private var cloudConfiguration: some View {
        Form {
            providerSection.listRowBackground(Theme.surface)
            connectionSection.listRowBackground(Theme.surface)
            voiceSection.listRowBackground(Theme.surface)
            voiceNotices
        }
        .scrollContentBackground(.hidden).background(Theme.bg).tint(Theme.accent)
        .navigationTitle("连接云语音").navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { previewing ? stopPreview() : testVoice() } label: {
                    Text(previewing ? "停止试听" : "试听")
                }
                .buttonStyle(SecondaryButtonStyle(height: 50))
                .accessibilityIdentifier("voice.preview")
                Button("保存并应用") { save() }
                    .buttonStyle(PrimaryButtonStyle(height: 50))
                    .accessibilityIdentifier("voice.save")
            }
            .padding(.horizontal, Theme.inset).padding(.vertical, 12)
            .frame(maxWidth: 760).frame(maxWidth: .infinity).background(Theme.bg)
        }
    }

    private var voiceNotices: some View {
        Section {
            Text(auditionHint).font(.caption).foregroundStyle(Theme.ink2)
            if let error { Text(error).font(.caption).foregroundStyle(Theme.danger) }
            if !notice.isEmpty { Text(L(notice)).font(.caption).foregroundStyle(Theme.ink2) }
        }
        .listRowBackground(Theme.accentSoft)
    }

    private var providerSection: some View {
        Section {
            Picker("提供方", selection: $provider) {
                Text("系统声音 · 离线").tag("system")
                Text("智谱 GLM · 中国区").tag("glm")
                Text("MiniMax · 中国区").tag("minimax")
                Text("Microsoft Azure").tag("azure")
                Text("ElevenLabs").tag("elevenlabs")
                Text("自定义 TTS（OpenAI 兼容）").tag("custom")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("voice.provider")
            .onChange(of: provider) { old, new in
                stopPreview()
                drafts[old] = Draft(voice: voice, model: modelName, key: apiKey, male: maleVoice, female: femaleVoice)
                fetchedVoices = []; notice = ""; error = nil
                load(new)
            }
        } header: { Text("选择朗读服务") } footer: { Text(providerNote) }
    }

    @ViewBuilder private var connectionSection: some View {
        if provider != "system" {
            Section {
                if provider == "glm" || provider == "minimax" {
                    LabeledContent("接入地区", value: "中国区")
                    Text(provider == "glm" ? "open.bigmodel.cn" : "api.minimax.cn")
                        .font(.caption).foregroundStyle(Theme.ink2)
                        .accessibilityIdentifier("voice.chinaEndpoint")
                    Link("打开中国区控制台", destination: URL(string: provider == "glm" ? "https://open.bigmodel.cn/" : "https://platform.minimax.cn/")!)
                }
                if provider == "custom" {
                    TextField("服务地址，如 https://example.com/v1", text: $customURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("voice.customURL")
                }
                SecureField(provider == "azure" ? "Speech Key（必填）" : provider == "custom" ? "API Key（自建服务可留空）" : "API Key（必填）", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("voice.apiKey")
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
                        TextField(provider == "glm" ? "模型 ID（需以 glm 开头，如 glm-tts）" : "模型 ID", text: $modelName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
            } header: { Text("连接 \(VoiceOptions.providerName(provider))") } footer: { Text(cloudNote) }
        }
    }

    private var voiceSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: Icon.voice).font(.system(size: 21)).foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44).background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        } header: { Text("音色") }
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
                ForEach(glmVoices, id: \.value) { v in
                    Text(v.label).tag(v.value)
                }
                if !glmVoices.contains(where: { $0.value == voice }) { Text("自定义音色").tag(voice) }
            }
            DisclosureGroup("自定义 / 复刻音色") {
                TextField("音色 ID（如 tongtong 或复刻音色 ID）", text: $voice)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } else if provider == "custom" {
            Picker("音色", selection: $voice) {
                ForEach(customVoices, id: \.value) { Text($0.label).tag($0.value) }
                if !customVoices.contains(where: { $0.value == voice }) { Text(voice.isEmpty ? "未填写" : voice).tag(voice) }
            }
            TextField("音色名（以你的服务为准）", text: $voice)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
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

    private var glmVoices: [CloudVoice] {
        [("tongtong", "彤彤"), ("chuichui", "锤锤"), ("xiaochen", "小陈"), ("jam", "动动"), ("kazi", "卡子"), ("douji", "豆吉"), ("luodo", "洛多")].map { CloudVoice(value: $0.0, label: $0.1) }
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
        case "custom": return "连接任何兼容 OpenAI /audio/speech 接口的朗读服务，包括自建或本机运行的 TTS。"
        default: return "使用你自己的 API Key 直连服务商，音质更自然，按服务商计费。"
        }
    }
    private var cloudNote: String {
        let privacy = "密钥只保存在本机钥匙串；朗读时会将当前句及后续少量句子发送给服务商预合成，试听也会联网，费用按服务商规则计算。"
        switch provider {
        case "glm": return "连接智谱中国区开放平台，使用 glm-tts 和中国区 API Key；聊天或编程套餐的密钥与额度是否包含语音，以控制台开通情况为准。" + privacy
        case "minimax": return "支持 MiniMax 国内版按量付费与 Token Plan（sk-cp- 开头）密钥，自动连接 api.minimax.cn。追求低延迟可选 speech-2.8-turbo。" + privacy
        case "azure": return "区域必须与 Azure 语音资源所在区域一致（在 Azure 门户的「密钥和终结点」中查看）。" + privacy
        case "elevenlabs": return "Flash 与 Turbo 模型延迟更低，Multilingual 适合长篇听书。" + privacy
        case "custom": return "只接受 https 地址，或局域网 / 本机的 http 地址。模型与音色名以你的服务为准。" + privacy
        default: return "不经过听页服务器。" + privacy
        }
    }
    private var presetModels: [String] {
        switch provider {
        case "glm": return ["glm-tts"]
        case "elevenlabs": return ["eleven_multilingual_v2", "eleven_turbo_v2_5", "eleven_flash_v2_5", "eleven_v3"]
        case "custom": return ["tts-1", "tts-1-hd", "gpt-4o-mini-tts"]
        default: return ["speech-2.8-hd", "speech-2.8-turbo", "speech-2.6-hd", "speech-2.6-turbo", "speech-02-hd", "speech-02-turbo", "speech-01-hd", "speech-01-turbo", "t2a-01-hd", "t2a-01"]
        }
    }
    private var customVoices: [CloudVoice] {
        ["alloy", "echo", "fable", "onyx", "nova", "shimmer"].map { CloudVoice(value: $0, label: $0) }
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
        case "glm":
            let cleaned = voice.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && !glmVoices.contains(where: { $0.value == cleaned }) {
                return glmVoices + [CloudVoice(value: cleaned, label: cleaned)]
            }
            return glmVoices
        case "azure": return AzureVoices.all
        case "elevenlabs": return elevenVoices
        case "custom": return customVoices
        default: return minimaxVoices
        }
    }

    private var currentVoiceName: String {
        if provider == "system" {
            if voice.isEmpty { return "默认中文声音" }
            return voices.first(where: { $0.identifier == voice })?.name ?? "默认中文声音"
        }
        if provider == "glm" {
            return glmVoices.first(where: { $0.value == voice })?.label ?? voice
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
        if provider == "custom" { return CloudSpeech.customSpeechEndpoint(customURL) == nil ? "请填写有效的自定义 TTS 地址（https，或局域网 / 本机 http）。" : nil }
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
        let config = (provider, chosen.model, chosen.voice, apiKey, provider == "azure" ? azureRegion : provider == "custom" ? customURL : groupID)
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
        maleVoice = VoiceOptions.sanitizedRoleVoice(provider: target, voice: d.string(forKey: VoiceOptions.roleKey("male", target)))
        femaleVoice = VoiceOptions.sanitizedRoleVoice(provider: target, voice: d.string(forKey: VoiceOptions.roleKey("female", target)))
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
            d.set(VoiceOptions.sanitizedRoleVoice(provider: target, voice: draft.male), forKey: VoiceOptions.roleKey("male", target))
            d.set(VoiceOptions.sanitizedRoleVoice(provider: target, voice: draft.female), forKey: VoiceOptions.roleKey("female", target))
        }
        d.set(provider, forKey: "voice.provider"); d.set(rate, forKey: "voice.rate")
        d.set(groupID, forKey: "voice.groupID"); d.set(azureRegion, forKey: "voice.azureRegion"); d.set(roles, forKey: "voice.roles")
        d.set(customURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: VoiceOptions.customURLKey)
        if provider == "elevenlabs", let label = elevenVoices.first(where: { $0.value == voice })?.label { d.set(label, forKey: "voice.label.elevenlabs." + voice) }
        stopPreview(); app.player.applyOptions(); dismiss()
    }

}

extension Double {
    /// 语速文字，最多两位小数：%.2g 会把 1.75 写成「1.8」。
    var rateText: String { formatted(.number.precision(.fractionLength(0...2))) }
}
