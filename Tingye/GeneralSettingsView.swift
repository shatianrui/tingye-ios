import SwiftUI
import UserNotifications

/// 通用设置的存储键，集中在一处，避免散落的字符串拼错。
enum GeneralSettings {
    static let resumeOnLaunchKey = "launch.resume"
    static let hapticsKey = "haptics.enabled"
    static let goalNoticeKey = "goal.notice"
    static let hideHomeIndicatorKey = "reader.hideHomeIndicator"
    static let keepAwakeKey = "reader.keepAwake"
    static var hapticsEnabled: Bool { UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true }
    static var goalNoticeEnabled: Bool { UserDefaults.standard.object(forKey: goalNoticeKey) as? Bool ?? true }

    /// 今天的累计时长刚跨过目标时提示一次（App 内提示；在后台听书时发本地通知）。
    @MainActor static func celebrateIfGoalReached(before: Double, after: Double, model: AppModel) {
        guard goalNoticeEnabled else { return }
        let goal = Double((UserDefaults.standard.object(forKey: "goal.dailyMinutes") as? Int ?? 30) * 60)
        guard before < goal, after >= goal else { return }
        let text = "今日 \(Int(goal / 60)) 分钟阅读目标已达成。"
        if UIApplication.shared.applicationState == .active {
            model.notify(text)
        } else {
            let content = UNMutableNotificationContent()
            content.title = "目标达成"; content.body = text; content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "tingye.goal." + AppModel.dayKey(Date()), content: content, trigger: nil))
        }
        // 达标后撤掉今天剩下的每日提醒。
        ReadingReminder.refresh(model: model)
    }
}

/// 通用设置：启动续读、达标提示、震动反馈、阅读时隐藏 Home 指示条。
struct GeneralSettingsView: View {
    @AppStorage(GeneralSettings.resumeOnLaunchKey) private var resumeOnLaunch = false
    @AppStorage(GeneralSettings.hapticsKey) private var haptics = true
    @AppStorage(GeneralSettings.goalNoticeKey) private var goalNotice = true
    @AppStorage(GeneralSettings.hideHomeIndicatorKey) private var hideHomeIndicator = true
    @AppStorage(GeneralSettings.keepAwakeKey) private var keepAwake = true
    @AppStorage(ComicPreset.defaultKey) private var comicMode = "ltr"

    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        return ["zh-Hans": "简体中文", "zh-Hant": "繁體中文", "en": "English", "ja": "日本語"][code] ?? code
    }

    var body: some View {
        Form {
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    HStack { Text("语言"); Spacer(); Text(currentLanguage).foregroundStyle(Theme.ink3) }
                }
                .accessibilityIdentifier("general.language")
            } footer: { Text("支持简体中文、繁體中文、English、日本語。在系统设置的「听页 › 语言」中切换。") }
            Section {
                Toggle("启动时自动继续上次阅读", isOn: $resumeOnLaunch)
                    .accessibilityIdentifier("general.resumeOnLaunch")
            } header: { Text("首页") } footer: { Text("打开 App 时直接回到最近阅读的那本书与位置。") }
            Section {
                Toggle("达成每日目标时提示", isOn: $goalNotice)
            } header: { Text("阅读目标") } footer: { Text("在 App 内显示提示；后台听书时以通知提醒。") }
            Section {
                Picker("默认阅读方式", selection: $comicMode) {
                    ForEach(ComicPreset.modes, id: \.value) { Text($0.label).tag($0.value) }
                }
                .accessibilityIdentifier("general.comicMode")
            } header: { Text("漫画") } footer: { Text("用于还没单独设置过的漫画；在漫画里切换方向只影响那一部。") }
            Section {
                Toggle("震动反馈", isOn: $haptics)
                Toggle("阅读时自动隐藏 Home 指示条", isOn: $hideHomeIndicator)
                Toggle("阅读与听书时保持屏幕常亮", isOn: $keepAwake)
            } header: { Text("交互") } footer: { Text("震动反馈只在部分按钮和翻页时出现；屏幕常亮只在阅读与听书页面生效，离开即恢复系统休眠。") }
        }
        .tint(Theme.clay)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("通用设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
