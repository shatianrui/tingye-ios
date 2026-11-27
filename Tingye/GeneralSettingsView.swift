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
        SettingsPage(title: "按你的习惯阅读", detail: "启动、语言与交互，只影响这台设备的使用习惯。") {
            SettingsGroup(footer: "支持简体中文、繁體中文、English、日本語。在系统设置的「听页 › 语言」中切换。") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: { HairlineRow(title: "语言", value: currentLanguage, disclosure: true, showsDivider: false) }
                .accessibilityIdentifier("general.language")
            }
            SettingsGroup(title: "首页", footer: "打开 App 时直接回到最近阅读的那本书与位置。") {
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
                SegmentedBar(options: ComicPreset.modes.map(\.value), selection: comicMode,
                             title: { value in ComicPreset.modes.first { $0.value == value }?.label ?? value },
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

/// 设置页面容器：清透系统下页面标题交给原生导航栏，内容采用接近 insetGrouped 的分组层级；其余方向保留节制报头。
struct SettingsPage<Content: View>: View {
    @Environment(\.themeDirection) private var themeDirection
    let title: String
    var detail: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        let _ = themeDirection
        let clear = AppThemeDirection.current == .systemClear
        ScrollView {
            VStack(alignment: .leading, spacing: clear ? 20 : Theme.sectionSpacing) {
                if clear {
                    if let detail, !detail.isEmpty {
                        Text(L(detail))
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                } else {
                    Masthead(title: title, subtitle: detail, rule: false, titleSize: 26)
                }
                content
            }
            .padding(.horizontal, clear ? Theme.insetCompact : Theme.inset)
            .padding(.top, clear ? Theme.space3 : Theme.space4)
            .padding(.bottom, Theme.space6)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .groupedBackground().foregroundStyle(Theme.ink).tint(Theme.accent)
    }
}

struct SettingsGroup<Content: View>: View {
    @Environment(\.themeDirection) private var themeDirection
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        let _ = themeDirection
        let clear = AppThemeDirection.current == .systemClear
        VStack(alignment: .leading, spacing: clear ? 6 : Theme.space3) {
            if let title {
                if clear {
                    Text(L(title))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 12)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    SectionHeader(title: title)
                }
            }
            PaperCard(padding: clear ? 16 : Theme.cardInset) {
                VStack(alignment: .leading, spacing: 0) { content }
            }
            if let footer {
                Text(L(footer))
                    .font(clear ? .footnote : Theme.sans(13))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, clear ? 12 : 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}
