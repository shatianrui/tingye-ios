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
        SettingsPage(title: "通用设置", detail: "语言、漫画和交互") {
            SettingsGroup(footer: "支持简体中文、繁體中文、English、日本語。在系统设置的「听页 › 语言」中切换。") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: { IndexRowLabel(title: Text("语言"), detail: Text(verbatim: currentLanguage), disclosure: true) }
                .accessibilityIdentifier("general.language")
            }
            SettingsGroup(title: "首页") {
                HairlineRow(showsDivider: false) {
                    Toggle("启动时自动继续上次阅读", isOn: $resumeOnLaunch)
                        .accessibilityIdentifier("general.resumeOnLaunch")
                }
            }
            SettingsGroup(title: "阅读目标", footer: "在 App 内显示提示；后台听书时以通知提醒。") {
                HairlineRow(showsDivider: false) { Toggle("达成每日目标时提示", isOn: $goalNotice) }
            }
            SettingsGroup(title: "漫画", footer: "用于还没单独设置过的漫画；在漫画里切换方向只影响那一部。") {
                Text("默认阅读方式").font(Theme.sans(15)).padding(.bottom, Theme.space2)
                IndexScopePicker(options: ComicPreset.modes.map(\.value), selection: comicMode,
                             title: { value in Text(L(ComicPreset.modes.first { $0.value == value }?.label ?? value)) },
                             onSelect: { comicMode = $0 })
                    .accessibilityIdentifier("general.comicMode")
            }
            SettingsGroup(title: "交互", footer: "震动反馈只在部分按钮和翻页时出现；屏幕常亮只在阅读与听书页面生效，离开即恢复系统休眠。") {
                HairlineRow { Toggle("震动反馈", isOn: $haptics) }
                HairlineRow { Toggle("阅读时自动隐藏 Home 指示条", isOn: $hideHomeIndicator) }
                HairlineRow(showsDivider: false) { Toggle("阅读与听书时保持屏幕常亮", isOn: $keepAwake) }
            }
        }
        .navigationTitle("通用设置").navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        IndexPage {
            IndexHeading(title: Text(L(title)), detail: detail.map { Text(L($0)) }, large: true)
            content
        }
        .foregroundStyle(IndexTheme.ink)
        .tint(IndexTheme.accent)
    }
}

struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            if let title { IndexHeading(title: Text(L(title))) }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, Theme.space3).padding(.vertical, Theme.space2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .indexPanel()
            if let footer {
                Text(L(footer)).font(.caption).foregroundStyle(IndexTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(PressButtonStyle())
    }
}
