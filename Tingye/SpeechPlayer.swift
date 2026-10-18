import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
import SwiftUI

enum SpeechAudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // Playback already supports AirPlay and A2DP. Explicit routing options
        // are for recording categories and can fail with paramErr (-50).
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
    }
}

struct VoiceOptions {
    var provider: String
    var model: String
    var voice: String
    var rate: Float
    var key: String
    var groupID: String
    /// 分角色配音：对话按说话人性别换男声 / 女声，旁白用 `voice`
    var roles = false
    var maleVoice = ""
    var femaleVoice = ""
    static func load() -> VoiceOptions {
        migrateLegacy()
        let d = UserDefaults.standard
        let provider = d.string(forKey: "voice.provider") ?? "system"
        let rate = d.float(forKey: "voice.rate")
        let chosen = sanitized(provider: provider, model: d.string(forKey: modelKey(provider)), voice: d.string(forKey: voiceKey(provider)))
        let group = provider == "azure" ? (d.string(forKey: "voice.azureRegion") ?? "") : (d.string(forKey: "voice.groupID") ?? "")
        var options = VoiceOptions(provider: provider, model: chosen.model, voice: chosen.voice, rate: min(2, max(0.5, rate == 0 ? 1 : rate)), key: apiKey(provider), groupID: group)
        options.roles = d.bool(forKey: "voice.roles")
        options.maleVoice = d.string(forKey: roleKey("male", provider)) ?? ""
        options.femaleVoice = d.string(forKey: roleKey("female", provider)) ?? ""
        return options
    }
    static func roleKey(_ role: String, _ provider: String) -> String { "voice.role.\(role).\(provider)" }
    static func providerName(_ provider: String) -> String {
        ["system": "系统声音", "glm": "智谱 GLM", "minimax": "MiniMax", "azure": "Microsoft Azure", "elevenlabs": "ElevenLabs"][provider] ?? provider
    }
    /// 某一句实际使用的配置：开启分角色时，对话句换成对应角色的音色
    func forRole(_ role: DialogueRole) -> VoiceOptions {
        guard roles else { return self }
        var next = self
        switch role {
        case .male where !maleVoice.isEmpty: next.voice = maleVoice
        case .female where !femaleVoice.isEmpty: next.voice = femaleVoice
        default: break
        }
        return next
    }

    // MARK: 按服务商分开保存（设置页与播放器共用同一套键）

    static func modelKey(_ provider: String) -> String { "voice.model." + provider }
    static func voiceKey(_ provider: String) -> String { "voice.name." + provider }
    static func secretKey(_ provider: String) -> String { "voice.key." + provider }
    static func apiKey(_ provider: String) -> String {
        guard provider != "system", let data = (try? Keychain.data(secretKey(provider))) ?? nil else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static let glmVoices = ["tongtong", "chuichui", "xiaochen", "jam", "kazi", "douji", "luodo"]
    static func defaultModel(_ provider: String) -> String {
        ["minimax": "speech-2.8-hd", "glm": "glm-tts", "elevenlabs": "eleven_multilingual_v2"][provider] ?? ""
    }
    static func defaultVoice(_ provider: String) -> String {
        ["minimax": "male-qn-qingse", "glm": "tongtong", "azure": "zh-CN-XiaoxiaoNeural", "elevenlabs": "21m00Tcm4TlvDq8ikWAM"][provider] ?? ""
    }
    /// 两家的模型与音色不通用：GLM 只用 glm 开头的模型和它的预设音色；MiniMax 不接受 GLM 的模型或音色。
    /// 已经串用的旧值在这里回到各自的默认值，避免把 GLM 的模型发给 MiniMax（或反过来）导致合成失败。
    static func sanitized(provider: String, model: String?, voice: String?) -> (model: String, voice: String) {
        var model = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var voice = (voice ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case "glm":
            if !model.lowercased().hasPrefix("glm") { model = defaultModel("glm") }
            if !glmVoices.contains(voice) { voice = defaultVoice("glm") }
        case "minimax":
            if model.isEmpty || model.lowercased().hasPrefix("glm") { model = defaultModel("minimax") }
            if voice.isEmpty || glmVoices.contains(voice) || voice.hasPrefix("com.apple.") { voice = defaultVoice("minimax") }
        case "azure":
            model = ""
            if !voice.hasSuffix("Neural") { voice = defaultVoice("azure") }
        case "elevenlabs":
            if !model.hasPrefix("eleven_") { model = defaultModel("elevenlabs") }
            if voice.isEmpty || voice.hasPrefix("com.apple.") || voice.hasSuffix("Neural") || glmVoices.contains(voice) { voice = defaultVoice("elevenlabs") }
        default:
            model = ""
            if !voice.isEmpty && !voice.hasPrefix("com.apple.") { voice = "" }
        }
        return (model, voice)
    }
    /// 旧版设置页把模型、音色、密钥存在不分服务商的键里（voice.model / voice.id / voice.key），
    /// 切换服务商时两家互相覆盖，播放器也读不到。按内容判断归属后迁到各自的键，只做一次。
    static func migrateLegacy(defaults d: UserDefaults = .standard, moveSecret: Bool = true) {
        let legacyModel = d.string(forKey: "voice.model")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyVoice = d.string(forKey: "voice.id")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacySecret = moveSecret ? ((try? Keychain.data("voice.key")) ?? nil) : nil
        guard legacyModel != nil || legacyVoice != nil || legacySecret != nil else { return }
        func owner(model: String?) -> String? {
            guard let model, !model.isEmpty else { return nil }
            return model.lowercased().hasPrefix("glm") ? "glm" : "minimax"
        }
        func owner(voice: String?) -> String? {
            guard let voice, !voice.isEmpty else { return nil }
            if voice.hasPrefix("com.apple.") { return "system" }
            return glmVoices.contains(voice) ? "glm" : "minimax"
        }
        if let provider = owner(model: legacyModel), d.string(forKey: modelKey(provider)) == nil { d.set(legacyModel, forKey: modelKey(provider)) }
        if let provider = owner(voice: legacyVoice), d.string(forKey: voiceKey(provider)) == nil { d.set(legacyVoice, forKey: voiceKey(provider)) }
        if let secret = legacySecret {
            let current = d.string(forKey: "voice.provider")
            let provider = owner(model: legacyModel) ?? owner(voice: legacyVoice).flatMap { $0 == "system" ? nil : $0 } ?? (current == "glm" || current == "minimax" ? current : nil)
            if let provider, apiKey(provider).isEmpty { try? Keychain.save(secret, key: secretKey(provider)) }
            try? Keychain.remove("voice.key")
        }
        d.removeObject(forKey: "voice.model"); d.removeObject(forKey: "voice.id")
    }
}

@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var book: Book?
    @Published private(set) var chapter = 0
    @Published private(set) var position = 0 { didSet { publishFollow() } }
    @Published private(set) var playing = false
    @Published private(set) var buffering = false
    @Published var error: String?
    /// 逐字进度不走 @Published：每读一个字都发 objectWillChange，会让整个阅读页（正文与底部悬浮面板）
    /// 一秒重算十几次。改由 `followPublisher` 单独推送，只有跟读翻页的地方订阅。
    private(set) var wordRange: NSRange? { didSet { publishFollow() } }
    @Published private(set) var timingLabel = "句子同步"
    /// 云端语音本句已读完最后一个字（只剩尾部静音），阅读页应立即翻到下一句所在页。
    private(set) var speechFinished = false { didSet { publishFollow() } }
    /// 当前应跟随的位置（即 `followOffset`），变化时推送。
    let followPublisher = CurrentValueSubject<Int?, Never>(nil)
    private func publishFollow() {
        let value = followOffset
        if followPublisher.value != value { followPublisher.send(value) }
    }
    private var spokenOffset = 0
    /// 系统语音预排队：当前句之后再排两句，合成器连续播放。短段落句子切换频繁，
    /// 若每句读完才回主线程停止、保存进度、重建下一句，句间会出现明显停顿。
    private var queued: [ObjectIdentifier: (line: AVSpeechUtterance, index: Int)] = [:]
    private var lastQueued = -1
    private static let lookahead = 2
    private var clockTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var cloudWords: [TimedWord] = []
    private var audioCache: [String: CloudClip] = [:]
    /// 正在合成的句子（按缓存键）：当前句与预取共用同一个请求。
    private var inflight: [String: Task<CloudClip, Error>] = [:]
    private static let cloudLookahead = 3
    private var cacheOrder: [String] = []
    struct TimedWord { let range: NSRange; let start: Double; let end: Double }
    struct CloudClip { let data: Data; let words: [TimedWord] }
    var sentenceRange: NSRange? { sentences.indices.contains(position) ? sentences[position].range : nil }
    /// 阅读页跟随朗读时应显示的位置：当前读到的字；本句读完则为下一句开头。
    var followOffset: Int? {
        guard let sentence = sentenceRange else { return nil }
        if speechFinished { return sentences.indices.contains(position + 1) ? sentences[position + 1].range.location : NSMaxRange(sentence) }
        return wordRange?.location ?? sentence.location
    }
    var allSentences: [Sentence] { sentences }
    var rate: Double { Double(options.rate) }

    @Published private(set) var sleepUntil: Date?
    var onProgress: ((String, Int, Int) -> Void)?
    private let synth = AVSpeechSynthesizer()
    private var audio: AVAudioPlayer?
    private var utterance: AVSpeechUtterance?
    private var task: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var generation = UUID()
    private var options = VoiceOptions.load()
    private var sentences: [Sentence] = []
    private var chapterList: [Chapter] = []
    private var resumeAfterInterruption = false
    private var observers: [NSObjectProtocol] = []
    var currentText: String { sentences.indices.contains(position) ? sentences[position].text : "" }
    var currentSentence: Sentence? { sentences.indices.contains(position) ? sentences[position] : nil }
    /// 指定位置之前最近的一句（用于在听书页展示"上一句"）
    func surroundingSentence(before index: Int) -> Sentence? {
        let i = max(0, index - 1); return sentences.indices.contains(i) ? sentences[i] : nil
    }
    /// 指定位置之后最近的一句（用于在听书页展示"下一句"）
    func surroundingSentence(after index: Int) -> Sentence? {
        let i = index + 1; return sentences.indices.contains(i) ? sentences[i] : nil
    }
    var count: Int { sentences.count }
    var progress: Double { sentences.isEmpty ? 0 : Double(position) / Double(max(1, sentences.count - 1)) }
    var chapterTitle: String { chapterList.indices.contains(chapter) ? chapterList[chapter].title : "" }
    var chapterCount: Int { chapterList.count }

    /// 当前朗读方式的展示标签
    var providerLabel: String {
        let base = ["system": "系统 · 离线", "glm": "智谱 GLM · 云端", "minimax": "MiniMax · 云端", "azure": "Azure · 云端", "elevenlabs": "ElevenLabs · 云端"][options.provider] ?? "离线"
        return options.roles ? base + " · 分角色" : base
    }
    /// 当前声音的展示标签
    var voiceLabel: String {
        switch options.provider {
        case "system":
            let id = options.voice
            if id.isEmpty { return "默认中文声音" }
            return AVSpeechSynthesisVoice(identifier: id)?.name ?? "系统声音"
        case "glm":
            let map = ["tongtong": "彤彤", "chuichui": "锤锤", "xiaochen": "小陈", "jam": "动动", "kazi": "卡子", "douji": "豆吉", "luodo": "洛多"]
            return map[options.voice] ?? options.voice
        case "minimax":
            let labels: [String: String] = [
                "male-qn-qingse": "青涩青年", "female-shaonv": "少女", "female-yujie": "御姐",
                "female-chengshu": "成熟女性", "female-tianmei": "甜美女性",
                "presenter_male": "男性主持人", "presenter_female": "女性主持人",
                "audiobook_male_1": "有声书男声 1", "audiobook_male_2": "有声书男声 2",
                "audiobook_female_1": "有声书女声 1", "audiobook_female_2": "有声书女声 2",
                "male-qn-jingying": "精英青年", "male-qn-badao": "霸道青年", "male-qn-daxuesheng": "大学生",
                "female-qn-qingse": "青涩女声", "female-qn-yujie": "御姐女声",
                "female-qn-chengshu": "成熟女声", "female-qn-tianmei": "甜美女声"
            ]
            return labels[options.voice] ?? options.voice
        case "azure":
            return AzureVoices.all.first { $0.value == options.voice }?.label ?? options.voice
        case "elevenlabs":
            return UserDefaults.standard.string(forKey: "voice.label.elevenlabs." + options.voice) ?? "ElevenLabs 音色"
        default:
            return options.voice
        }
    }

    override init() {
        super.init(); synth.delegate = self
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(1) }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-1) }; return .success }
        // 锁屏 / 控制中心拖动进度条：按估算的朗读时长换算成句子位置。
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self?.seek(toEstimatedTime: time) }
            return .success
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0).contains(.shouldResume)
            Task { @MainActor in
                guard let self else { return }
                if type == .began { if self.playing { self.pause(); self.resumeAfterInterruption = true } }
                else if type == .ended { let resume = self.resumeAfterInterruption && shouldResume; self.resumeAfterInterruption = false; if resume { self.resume() } }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } }
        })
    }
    func start(book: Book, chapter: Int, position: Int) {
        // 先在阅读页设了定时再开始听，换书重建朗读时保留剩余时间。
        let pendingSleep = sleepUntil
        stop(); if let pendingSleep { setSleep(until: pendingSleep) }
        self.book = book; options = .load(); chapterList = book.chapters
        guard !chapterList.isEmpty else { self.book = nil; return }
        self.chapter = min(max(chapter, 0), chapterList.count - 1)
        sentences = Sentence.split(chapterList[self.chapter].text)
        self.position = min(max(position, 0), max(0, sentences.count - 1))
        playing = true; playSentence()
    }
    func toggle() { playing ? pause() : resume() }
    func pause() {
        playing = false; buffering = false; generation = UUID(); task?.cancel(); task = nil
        if synth.isSpeaking { synth.pauseSpeaking(at: .immediate) }
        audio?.pause(); updateNowPlaying()
    }
    func resume() {
        guard book != nil else { return }
        guard prepareAudioSession() else { return }
        error = nil; playing = true; resumeAfterInterruption = false
        if synth.isPaused {
            if !synth.continueSpeaking() { pause(); error = "朗读未能恢复，请重新选择当前句重试。" }
            updateNowPlaying()
        }
        else if let audio, audio.currentTime < audio.duration {
            if !audio.play() { pause(); error = "音频未能恢复，请重新选择当前句重试。" }
            updateNowPlaying()
        }
        else { playSentence() }
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil; utterance = nil; audio?.delegate = nil
        synth.stopSpeaking(at: .immediate); queued = [:]; audio?.stop(); audio = nil
        playing = false; buffering = false; error = nil; book = nil; sentences = []; chapterList = []; wordRange = nil; speechFinished = false; spokenOffset = 0; resumeAfterInterruption = false
        clockTask?.cancel(); prefetchTask?.cancel(); cloudWords = []; audioCache = [:]; cacheOrder = []
        inflight.values.forEach { $0.cancel() }; inflight = [:]
        setSleep(minutes: 0); MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func skip(_ delta: Int) { seek(position + delta) }
    func seek(_ index: Int) {
        guard let book else { return }
        let chapters = chapterList
        generation = UUID(); task?.cancel(); utterance = nil; synth.stopSpeaking(at: .immediate); queued = [:]; audio?.delegate = nil; audio?.stop(); audio = nil
        if index >= sentences.count {
            if chapter + 1 < chapters.count { chapter += 1; sentences = Sentence.split(chapters[chapter].text); position = 0 }
            else { playing = false; position = max(0, sentences.count - 1); buffering = false; updateNowPlaying(); return }
        } else if index < 0, chapter > 0 { chapter -= 1; sentences = Sentence.split(chapters[chapter].text); position = max(0, sentences.count - 1) }
        else { position = min(max(0, index), max(0, sentences.count - 1)) }
        spokenOffset = 0; wordRange = nil; speechFinished = false; cloudWords = []; clockTask?.cancel()
        onProgress?(book.id, chapter, position)
        if playing { playSentence() } else { buffering = false; updateNowPlaying() }
    }
    func changeRate(_ value: Double) {
        UserDefaults.standard.set(value, forKey: "voice.rate"); options.rate = Float(value)
        if let audio { audio.rate = options.rate; updateNowPlaying(); return }
        restartAtCurrentWord()
    }
    func applyOptions() {
        let previous = options; options = .load()
        if previous.provider == options.provider && previous.model == options.model && previous.voice == options.voice && previous.key == options.key && previous.groupID == options.groupID {
            changeRate(Double(options.rate)); return
        }
        restartAtCurrentWord()
    }
    private func restartAtCurrentWord() {
        let wasPlaying = playing
        if let range = wordRange, let sentenceRange { spokenOffset = max(0, range.location - sentenceRange.location) }
        generation = UUID(); task?.cancel(); prefetchTask?.cancel(); clockTask?.cancel()
        utterance = nil; synth.stopSpeaking(at: .immediate); queued = [:]; audio?.delegate = nil; audio?.stop(); audio = nil
        buffering = false; speechFinished = false; playing = wasPlaying
        if wasPlaying { playSentence() }
    }
    func skipChapter(_ delta: Int) {
        guard book != nil, chapterList.indices.contains(chapter + delta) else { return }
        chapter += delta; sentences = Sentence.split(chapterList[chapter].text); seek(0)
    }
    func seek(chapter target: Int, position: Int) {
        guard book != nil, chapterList.indices.contains(target) else { return }
        chapter = target; sentences = Sentence.split(chapterList[target].text); seek(position)
    }
    func setSleep(minutes: Int) { setSleep(until: minutes > 0 ? Date().addingTimeInterval(Double(minutes * 60)) : nil) }
    private func setSleep(until date: Date?) {
        sleepTask?.cancel(); sleepUntil = date.flatMap { $0 > Date() ? $0 : nil }
        guard let until = sleepUntil else { return }
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(until.timeIntervalSinceNow)) } catch { return }
            self?.pause(); self?.sleepUntil = nil
        }
    }
    private func prepareAudioSession() -> Bool {
        do {
            try SpeechAudioSession.activate()
            return true
        } catch {
            pause()
            let failure = error as NSError
            self.error = "无法启动朗读音频（\(failure.domain)：\(failure.code)），请重试。"
            return false
        }
    }
    private func playSentence() {
        guard playing, let book else { return }
        if let sleepUntil, sleepUntil <= Date() { pause(); setSleep(minutes: 0); return }
        guard sentences.indices.contains(position) else {
            // Skip empty / illustration-only chapters without recursive calls.
            task = Task { [weak self] in self?.seek((self?.sentences.count ?? 0)) }; return
        }
        guard prepareAudioSession() else { return }
        onProgress?(book.id, chapter, position); updateNowPlaying()
        if options.provider == "system" {
            let offset = min(spokenOffset, max(0, (currentText as NSString).length - 1))
            spokenOffset = offset; timingLabel = "句子同步"
            let line = makeUtterance((currentText as NSString).substring(from: offset), sentence: position)
            queued = [ObjectIdentifier(line): (line, position)]; lastQueued = position
            utterance = line; synth.speak(line); buffering = false
            enqueueAhead()
        } else {
            let marker = UUID(); generation = marker; buffering = true; speechFinished = false; timingLabel = "正在合成"
            let offset = min(spokenOffset, max(0, (currentText as NSString).length - 1))
            let content = (currentText as NSString).substring(from: offset), config = options.forRole(role(position)), base = options
            // 当前句一开始合成就同时预取后面几句（已缓存的跳过），切句时下一句通常已就绪。
            prefetch(after: position, options: base)
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    let clip = try await self.cloudClip(content, options: config)
                    try Task.checkCancellation()
                    guard self.generation == marker, self.playing else { return }
                    let audio = try AVAudioPlayer(data: clip.data); audio.enableRate = true; audio.rate = config.rate; audio.delegate = self; audio.prepareToPlay()
                    self.audio = audio; self.cloudWords = clip.words; self.buffering = false
                    self.timingLabel = "句子同步"
                    guard audio.play() else { throw ReaderError.message("音频无法播放，请重试或切换系统声音。") }
                    self.clockTask?.cancel()
                    self.clockTask = Task { [weak self, weak audio] in
                        while !Task.isCancelled {
                            guard let self, let audio, self.audio === audio else { return }
                            if self.playing, !self.speechFinished, let last = self.cloudWords.last, audio.currentTime >= last.end { self.speechFinished = true }
                            // 本句最后一个字已读完、只剩音频尾部静音，且下一句已合成好：直接接下一句，不等静音放完。
                            if self.playing, self.speechFinished, let last = self.cloudWords.last, audio.currentTime >= last.end + 0.12,
                               self.sentences.indices.contains(self.position + 1), self.cachedClip(self.sentences[self.position + 1].text, options: base.forRole(self.role(self.position + 1))) != nil {
                                audio.delegate = nil; self.skip(1); return
                            }
                            if self.playing, let word = self.cloudWords.first(where: { audio.currentTime >= $0.start && audio.currentTime < $0.end }), let sentence = self.sentenceRange {
                                self.wordRange = NSRange(location: sentence.location + offset + word.range.location, length: word.range.length)
                            }
                            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
                        }
                    }
                } catch is CancellationError {} catch {
                    guard self.generation == marker else { return }
                    self.error = error.localizedDescription; self.buffering = false; self.playing = false; self.updateNowPlaying()
                }
            }

        }
    }
    private func clipKey(_ text: String, options config: VoiceOptions) throws -> String {
        let body: [String: JSONValue] = ["provider": .string(config.provider), "model": .string(config.model), "voice": .string(config.voice), "key": .string(config.key), "groupId": .string(config.groupID), "input": .string(text)]
        return Integrity.sha256(try Integrity.encoder().encode(body))
    }
    private func cachedClip(_ text: String, options config: VoiceOptions) -> CloudClip? {
        (try? clipKey(text, options: config)).flatMap { audioCache[$0] }
    }
    private func cloudClip(_ text: String, options config: VoiceOptions) async throws -> CloudClip {
        let key = try clipKey(text, options: config)
        if let cached = audioCache[key] { return cached }
        // 同一句已在合成（多为预取）：直接等它完成，不再重复请求。旧实现会再发一次请求，
        // 句间要多等一整个网络往返，这是朗读卡顿的主要原因。
        if let running = inflight[key] { return try await running.value }
        let request = Task { [weak self] () throws -> CloudClip in
            guard let self else { throw CancellationError() }
            defer { self.inflight[key] = nil }
            return try await self.synthesizeClip(text, key: key, options: config)
        }
        inflight[key] = request
        return try await request.value
    }
    private func synthesizeClip(_ text: String, key: String, options config: VoiceOptions) async throws -> CloudClip {
        var result: CloudSpeech.Result? = await Task.detached(priority: .userInitiated) {
            CloudSpeech.cachedResult(forKey: key)
        }.value
        if result == nil {
            for attempt in 0...2 {
                do {
                    let fetched = try await CloudSpeech.synthesize(text, provider: config.provider, model: config.model, voice: config.voice, key: config.key, groupID: config.groupID)
                    result = fetched
                    Task.detached(priority: .utility) { CloudSpeech.storeCachedResult(fetched, forKey: key) }
                    break
                } catch {
                    try Task.checkCancellation()
                    guard attempt < 2 else { throw error }
                    if let apiError = error as? APIError, apiError.status == 429, apiError.retryAfter > 0, apiError.retryAfter <= 120 { try await Task.sleep(for: .seconds(apiError.retryAfter * Double(attempt + 1))) }
                    else if let network = error as? URLError, [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(network.code) { try await Task.sleep(for: .milliseconds(400 * (attempt + 1))) }
                    else { throw error }
                }
            }
        }
        guard let result else { throw ReaderError.message("语音请求失败。") }
        let audioData = result.audio, source = text as NSString
        var timed = result.words
        if timed.isEmpty, let span = CloudSpeech.speechSpan(wav: audioData) ?? (try? AVAudioPlayer(data: audioData)).map({ (start: 0.0, end: $0.duration) }) {
            timed = CloudSpeech.estimatedWords(text, from: span.start, to: span.end)
        }
        var words: [TimedWord] = [], cursor = 0
        for word in timed {
            let range = source.range(of: word.text, range: NSRange(location: cursor, length: source.length - cursor))
            guard range.location != NSNotFound, range.length > 0 else { continue }
            words.append(TimedWord(range: range, start: word.start, end: word.end)); cursor = NSMaxRange(range)
        }
        let clip = CloudClip(data: audioData, words: words)
        audioCache[key] = clip; cacheOrder.removeAll { $0 == key }; cacheOrder.append(key)
        while audioCache.values.reduce(0, { $0 + $1.data.count }) > 32 * 1024 * 1024, let first = cacheOrder.first { audioCache[first] = nil; cacheOrder.removeFirst() }
        return clip
    }
    /// 预取当前句之后的几句：与当前句的合成同时开始，而不是等当前句开始播放才排队。
    /// 依次请求（同时最多一条预取 + 当前句一条），避免触发服务商限流；已缓存或正在合成的句子直接跳过。
    private func prefetch(after index: Int, options config: VoiceOptions) {
        let upcoming = (1...Self.cloudLookahead).compactMap { sentences.indices.contains(index + $0) ? (sentences[index + $0].text, config.forRole(role(index + $0))) : nil }
        guard !upcoming.isEmpty else { return }
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            for (next, options) in upcoming {
                guard !Task.isCancelled, let self, self.playing else { return }
                _ = try? await self.cloudClip(next, options: options)
            }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance, let sentence = self.sentenceRange else { return }
            self.wordRange = NSRange(location: sentence.location + self.spokenOffset + characterRange.location, length: characterRange.length)
        }
    }
    /// 第 index 句的角色（未开启分角色时一律旁白）
    private func role(_ index: Int) -> DialogueRole { options.roles ? DialogueRoles.role(index, in: sentences) : .narrator }
    private func makeUtterance(_ text: String, sentence index: Int) -> AVSpeechUtterance {
        let line = AVSpeechUtterance(string: text)
        let voice = options.forRole(role(index)).voice
        line.voice = AVSpeechSynthesisVoice(identifier: voice) ?? AVSpeechSynthesisVoice(identifier: options.voice) ?? AVSpeechSynthesisVoice(language: "zh-CN")
        line.rate = AVSpeechUtteranceDefaultSpeechRate * options.rate
        return line
    }
    /// 在当前句之后补足预排的句子（只排本章内的；跨章仍走 skip 重建）。
    private func enqueueAhead() {
        guard playing, options.provider == "system" else { return }
        while lastQueued < position + Self.lookahead, sentences.indices.contains(lastQueued + 1) {
            lastQueued += 1
            let line = makeUtterance(sentences[lastQueued].text, sentence: lastQueued)
            queued[ObjectIdentifier(line)] = (line, lastQueued)
            synth.speak(line)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            // 预排的下一句开始播放：只推进位置与进度，不打断合成器。
            guard let self, let book = self.book, self.playing, utterance !== self.utterance,
                  let index = self.queued[ObjectIdentifier(utterance)]?.index else { return }
            if let sleepUntil = self.sleepUntil, sleepUntil <= Date() { self.pause(); self.setSleep(minutes: 0); return }
            self.utterance = utterance; self.position = index
            self.spokenOffset = 0; self.wordRange = nil; self.speechFinished = false
            self.onProgress?(book.id, self.chapter, index); self.updateNowPlaying()
            self.enqueueAhead()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.queued[ObjectIdentifier(utterance)] = nil
            guard self.utterance === utterance, self.playing else { return }
            // 后面还有预排的句子，合成器会接着读，由 didStart 推进位置。
            if self.queued.values.contains(where: { $0.index > self.position }) { return }
            self.utterance = nil; self.skip(1)
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, player === self.audio, self.playing else { return }
            if flag { self.skip(1) } else { self.pause(); self.error = "音频播放中断，请重试。" }
        }
    }
    // MARK: - 锁屏 / 控制中心「正在播放」

    private var artwork: (id: String, value: MPMediaItemArtwork)?
    private var lengths: (chapter: Int, count: Int, prefix: [Int])?
    /// 朗读没有真实时长：按每秒约 4.5 字（随语速缩放）估算，供锁屏进度条显示与拖动。
    private var charactersPerSecond: Double { 4.5 * Double(max(0.5, options.rate)) }
    /// 本章各句起点的累计字数（末项为全章字数），换章时重算。
    private var prefixLengths: [Int] {
        if let lengths, lengths.chapter == chapter, lengths.count == sentences.count { return lengths.prefix }
        var prefix = [0]; prefix.reserveCapacity(sentences.count + 1)
        for sentence in sentences { prefix.append(prefix[prefix.count - 1] + sentence.range.length) }
        lengths = (chapter, sentences.count, prefix); return prefix
    }
    private func seek(toEstimatedTime time: TimeInterval) {
        let prefix = prefixLengths
        guard prefix.count > 1 else { return }
        let target = Int(time * charactersPerSecond)
        let index = (prefix.lastIndex(where: { $0 <= target }) ?? 0)
        seek(min(index, sentences.count - 1))
    }
    private func artwork(for book: Book) -> MPMediaItemArtwork {
        if let artwork, artwork.id == book.id { return artwork.value }
        let image = book.coverData.flatMap(UIImage.init(data:))?.preparingThumbnail(of: CGSize(width: 600, height: 600)) ?? Self.typographicCover(book)
        let value = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        artwork = (book.id, value); return value
    }
    /// 没有封面的书：书封色块 + 书名首字，与书架上的文字封面一致。
    private static func typographicCover(_ book: Book) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size).image { context in
            // Media artwork is cached independently from the current window appearance.
            let traits = UITraitCollection(userInterfaceStyle: .light)
            Theme.coverUIColor(book.color).resolvedColor(with: traits).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let glyph = String(book.title.prefix(1)) as NSString
            let font = UIFont(name: Theme.serifName, size: 260) ?? .systemFont(ofSize: 260, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Theme.ink).resolvedColor(with: traits)]
            let bounds = glyph.size(withAttributes: attributes)
            glyph.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2), withAttributes: attributes)
        }
    }
    private func updateNowPlaying() {
        guard let book else { return }
        let prefix = prefixLengths
        let total = Double(prefix.last ?? 0), spoken = Double(prefix[min(position, prefix.count - 1)])
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: book.title,
            MPMediaItemPropertyArtist: book.author,
            MPMediaItemPropertyAlbumTitle: chapterTitle,
            MPMediaItemPropertyArtwork: artwork(for: book),
            MPMediaItemPropertyPlaybackDuration: total / charactersPerSecond,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: spoken / charactersPerSecond,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyChapterNumber: chapter,
            MPNowPlayingInfoPropertyChapterCount: chapterList.count
        ]
    }
}
