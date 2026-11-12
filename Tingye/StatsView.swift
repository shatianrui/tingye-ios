import SwiftUI
import Charts
import UserNotifications

/// 统计（参照 PureLibro）：日 / 周 / 月 / 年 / 总；概览数字、阅读目标、时长图表、阅读时段、按书排行。
/// 按日的总时长来自 `readingSeconds`（旧版本也有）；时段与排行来自 1.14 起记录的 `sessions`。
struct StatsView: View {
    @EnvironmentObject var model: AppModel
    /// 我的概览与独立阅读统计共用数据；设置保留单独的导航层级。
    var ji = false
    /// 被推入外层导航栈（书房根的「我的」）时的返回动作。ji 版本页隐藏系统导航栏，
    /// 没有系统返回箭头，故由页眉自带返回按钮调用此闭包弹出导航栈；
    /// 为 nil 时不渲染返回按钮（独立统计页等既有用法行为不变）。
    var onBack: (() -> Void)? = nil
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @AppStorage(ReadingReminder.enabledKey) private var reminderEnabled = false
    @AppStorage(ReadingReminder.minutesKey) private var reminderMinutes = ReadingReminder.defaultMinutes
    @State private var reminderDraft = false
    @State private var reminderTime = Date()
    @State private var reminderDenied = false
    @State private var period: Period = .day
    @State private var offset = 0
    @State private var editingGoal = false
    @State private var goalDraft = 30
    @State private var export: ExportedBook?
    @State private var settingsRoute: SettingsDestination?
    @State private var showingCalendar = false
    @State private var showingStats = false
    @State private var showingSettings = false
    @ScaledMetric(relativeTo: .largeTitle) private var durationSize = 36
    @Environment(\.dynamicTypeSize) private var typeSize
    private var summaryLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
    }

    enum Period: String, CaseIterable, Identifiable {
        case day = "日", week = "周", month = "月", year = "年", all = "全部"
        var id: String { rawValue }
        var component: Calendar.Component? {
            switch self { case .day: .day; case .week: .weekOfYear; case .month: .month; case .year: .year; case .all: nil }
        }
    }

    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    /// 当前查看的时间区间
    private var interval: DateInterval {
        guard let component = period.component,
              let anchor = calendar.date(byAdding: component, value: offset, to: Date()),
              let value = calendar.dateInterval(of: component, for: anchor) else {
            let first = model.readingSeconds.keys.sorted().first.flatMap(Self.date(fromKey:)) ?? Date()
            return DateInterval(start: calendar.startOfDay(for: first), end: Date())
        }
        return value
    }
    private var dayTotals: [(date: Date, seconds: Double)] {
        model.readingSeconds.compactMap { key, seconds in Self.date(fromKey: key).map { ($0, seconds) } }
            .filter { interval.contains($0.0) }
            .sorted { $0.0 < $1.0 }
    }
    private var totalSeconds: Double { dayTotals.reduce(0) { $0 + $1.seconds } }
    private var periodSessions: [ReadingSession] { model.visibleSessions.filter { interval.contains($0.start) } }
    /// 「我的」页眉摘要口径：累计阅读为 readingSeconds 全量汇总（与书库既有总时长同一来源）。
    private var totalReadingText: String {
        let minutes = Int(model.readingSeconds.values.reduce(0, +) / 60)
        return minutes >= 60 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if ji { profileContent }
                else { statisticsContent }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationTitle(ji ? "我的" : "阅读足迹")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(ji ? .hidden : .visible, for: .navigationBar)
        .navigationDestination(isPresented: $showingStats) {
            StatsView().environmentObject(model)
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(isPresented: $showingSettings) {
            SettingsDirectoryView().environmentObject(model)
                .toolbar(.visible, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(item: $settingsRoute) { route in
            settingsDestinationView(route)
                .toolbar(.visible, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        }
        #if DEBUG
        .task {
            if let screen = UIReview.screen, settingsRoute == nil {
                if screen == "appearance" { settingsRoute = .appearance }
                else if screen == "backup" { settingsRoute = .backup }
                else if screen == "privacy" { settingsRoute = .profile }
                else if screen == "settings" { showingSettings = true }
                else if screen == "stats-detail" && ji { showingStats = true }
            }
        }
        #endif
        #if DEBUG
        .task { if UIReview.screen == "stats-goal" { editGoal() } }
        #endif
        .sheet(isPresented: $editingGoal) { goalEditor }
        .sheet(isPresented: $showingCalendar) { ReadingCalendarView().environmentObject(model).tint(Theme.accent) }
        .sheet(item: $export) { ShareSheet(items: [$0.url]) }
    }

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                if let onBack {
                    Button { onBack() } label: {
                        ThemeIcon(symbol: Icon.back, size: 20, weight: .medium)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.92))
                    .accessibilityLabel("返回")
                    .accessibilityIdentifier("study.profileBack")
                }
                Text("我的").scaledFont(28, weight: .bold, relativeTo: .title)
                Spacer()
                Button { showingSettings = true } label: {
                    ThemeIcon(symbol: Icon.settings, size: 22).frame(width: 44, height: 44)
                }
                .accessibilityLabel("设置")
                .accessibilityIdentifier("profile.settings")
            }
            Text("在每一天，留下阅读的痕迹。")
                .font(.caption).foregroundStyle(Theme.ink2)
            Text("藏书 \(model.visibleEntries.count) 本 · 累计阅读 \(totalReadingText)")
                .font(.caption).foregroundStyle(Theme.ink2)
            monthlyFootprint
            profileEntry("阅读足迹", value: "查看统计") { showingStats = true }
                .accessibilityIdentifier("profile.stats")
            profileEntry("我的书摘", value: "\(model.noteCount) 条") { settingsRoute = .notes }
                .accessibilityIdentifier("profile.notes")
            if model.visibleEntries.contains(where: { $0.local && !$0.isComic }) {
                DailyQuoteCard(compact: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("今日摘句").font(.caption2.weight(.medium))
                    Text("把日子过慢一点，\n让喜欢的文字多停留一会儿。")
                        .font(Theme.serifSemibold(23, relativeTo: .title2)).lineSpacing(7)
                    Text("听页 · 今日阅读寄语").font(.caption).foregroundStyle(Theme.onWarm)
                }
                .foregroundStyle(Theme.onWarm)
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warm, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
                .softCardShadow()
            }
            profileEntry("设置", value: "阅读 · 声音 · 数据") { showingSettings = true }
            Text("无需账号，你的书留在你的设备。")
                .font(.caption).foregroundStyle(Theme.ink2)
        }
        .foregroundStyle(Theme.ink)
    }

    private var monthlyFootprint: some View {
        let currentMonth = calendar.dateInterval(of: .month, for: Date())
        let seconds = model.readingSeconds.reduce(0.0) { total, item in
            guard let date = Self.date(fromKey: item.key), currentMonth?.contains(date) == true else { return total }
            return total + item.value
        }
        let finished = model.visibleEntries.filter { $0.started && $0.readFraction >= 0.995 }.count
        let streak = AppModel.readingStreak(model.readingSeconds).current
        return Button { showingStats = true } label: {
            VStack(alignment: .leading, spacing: 16) {
                Text("这个月，读听了").font(.caption)
                Text(Self.preciseDuration(seconds)).scaledFont(36, weight: .bold, relativeTo: .largeTitle)
                    .minimumScaleFactor(0.6).lineLimit(1).monospacedDigit()
                ViewThatFits(in: .horizontal) {
                    HStack { Text("累计读完 \(finished) 本"); Spacer(); Text("连续阅读 \(streak) 天") }
                    VStack(alignment: .leading, spacing: 6) { Text("累计读完 \(finished) 本"); Text("连续阅读 \(streak) 天") }
                }
                .font(.caption)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
            .softCardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看完整阅读统计")
    }

    private func profileEntry(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text(value).font(.caption).foregroundStyle(Theme.ink2)
                ThemeIcon(symbol: Icon.disclosure, size: 16).foregroundStyle(Theme.ink2)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statisticsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if period != .all { periodNavigation }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Period.allCases) { item in
                        Button { period = item } label: {
                            Text(L(item.rawValue)).font(.caption.weight(.medium))
                                .foregroundStyle(period == item ? Theme.onAccent : Theme.ink2)
                                .padding(.horizontal, 16).frame(minHeight: 40)
                                .background(period == item ? Theme.accent : Theme.surface2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(period == item ? .isSelected : [])
                        .accessibilityLabel("按" + item.rawValue + "查看")
                    }
                }
            }
            .onChange(of: period) { _, _ in offset = 0 }
            VStack(alignment: .leading, spacing: 14) { header; chart }
                .padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
                .softCardShadow()
            goalCard
            sessionsCard
            Button("导出阅读记录") { exportStats() }
                .buttonStyle(SecondaryButtonStyle(height: 50))
            ranking
            overview
        }
    }

    private static func preciseDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
    }

    // MARK: 头部：总时长 + 区间与前后切换

    private var header: some View {
        let reading = periodSessions.filter { !$0.listening }.reduce(0) { $0 + $1.seconds }
        let listening = periodSessions.filter(\.listening).reduce(0) { $0 + $1.seconds }
        let unclassified = max(0, totalSeconds - reading - listening)
        return VStack(alignment: .leading, spacing: 10) {
            Text(period == .day && offset == 0 ? "今天读听时长" : "本期读听时长")
                .font(.caption).foregroundStyle(Theme.ink2)
            Text(Self.preciseDuration(totalSeconds))
                .font(.system(size: durationSize, weight: .bold)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(Theme.ink)
            summaryLayout {
                Text("阅读 " + Self.preciseDuration(reading))
                Text("听书 " + Self.preciseDuration(listening))
            }
            .font(.caption).foregroundStyle(Theme.ink2)
            if unclassified >= 60 {
                Text("另有 \(Int(unclassified / 60)) 分钟旧版记录未区分阅读与听书")
                    .font(.caption2).foregroundStyle(Theme.ink2)
            }
            if period == .all { Text(intervalLabel).font(.caption).foregroundStyle(Theme.ink2) }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var periodNavigation: some View {
        let unit = period == .day ? "天" : period.rawValue
        let current = period == .day ? "今天" : period == .week ? "本周" : period == .month ? "本月" : "今年"
        return HStack(spacing: 4) {
            Button { offset -= 1 } label: {
                ThemeIcon(symbol: Icon.back, size: 18).frame(width: 44, height: 44)
            }
            .accessibilityLabel("上一" + unit)
            Button { offset = 0 } label: {
                Text(intervalLabel).font(.caption).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityHint(offset == 0 ? "正在显示" + current : "轻点回到" + current)
            Button { offset = min(0, offset + 1) } label: {
                ThemeIcon(symbol: Icon.disclosure, size: 18).frame(width: 44, height: 44)
            }
            .accessibilityLabel("下一" + unit)
            .disabled(offset >= 0).opacity(offset >= 0 ? 0.3 : 1)
        }
        .buttonStyle(.plain).foregroundStyle(Theme.ink2)
        .padding(.vertical, -8)
    }

    private func editGoal() {
        goalDraft = goalMinutes
        reminderDraft = reminderEnabled
        reminderDenied = false
        reminderTime = Calendar.current.date(byAdding: .minute, value: reminderMinutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        editingGoal = true
    }

    private var intervalLabel: String {
        let i = interval
        // 日期格式跟随界面语言（简中仍为「2026年10月22日 星期四」）。
        let f = DateFormatter(); f.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "zh-Hans")
        switch period {
        case .day: f.setLocalizedDateFormatFromTemplate("yMMMdEEEE"); return f.string(from: i.start)
        case .week:
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return f.string(from: i.start) + " – " + f.string(from: i.end.addingTimeInterval(-1))
        case .month: f.setLocalizedDateFormatFromTemplate("yMMMM"); return f.string(from: i.start)
        case .year: f.setLocalizedDateFormatFromTemplate("y"); return f.string(from: i.start)
        case .all:
            f.setLocalizedDateFormatFromTemplate("yMMMd")
            return "自 " + f.string(from: i.start) + " 起 · \(dayTotals.filter { $0.seconds > 0 }.count) 天"
        }
    }

    // MARK: 概览

    private var overview: some View {
        let ids = Set(periodSessions.map(\.bookID))
        let finished = model.entries.filter { $0.started && $0.readFraction >= 0.995 }.count
        return VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "阅读概览")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 18) {
                GridRow {
                    metric("本期在读", period == .all ? model.entries.filter(\.started).count : ids.count, "本", icon: Icon.read)
                    metric("累计读完", finished, "本", icon: Icon.markRead)
                }
                RowDivider().gridCellColumns(2)
                GridRow {
                    metric("本期阅读", periodSessions.count, "次", icon: Icon.duration)
                    metric("全部笔记书摘", model.noteCount, "条", icon: Icon.noteStat)
                }
                RowDivider().gridCellColumns(2)
                GridRow {
                    let streak = AppModel.readingStreak(model.readingSeconds)
                    metric("连续阅读", streak.current, "天", icon: Icon.autoTurn)
                        .accessibilityIdentifier("stats.streak")
                    metric("最长连续", streak.longest, "天", icon: Icon.markRead)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int, _ unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) { ThemeIcon(symbol: icon, size: 16); Text(L(title)) }
                .font(.caption)
                .foregroundStyle(Theme.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(value)").scaledFont(28, weight: .heavy, relativeTo: .title2).monospacedDigit().foregroundStyle(Theme.ink)
                Text(L(unit)).font(.caption).foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: 阅读目标

    private var goalCard: some View {
        let today = model.readingSeconds[AppModel.dayKey(Date())] ?? 0
        let fraction = min(1, today / Double(max(1, goalMinutes) * 60))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("每日目标").scaledFont(20, weight: .bold, relativeTo: .title3)
                Spacer()
                Button("修改") { editGoal() }.font(.caption).frame(minHeight: 44)
            }
            Button { editGoal() } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("今天 \(Int(today / 60)) / \(goalMinutes) 分钟").font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        Text(fraction >= 1 ? "已完成 ✓" : "\(Int(fraction * 100))%")
                            .font(.caption).monospacedDigit()
                    }
                    ProgressBar(value: fraction, track: Theme.line, tint: Theme.accent, height: 4)
                }
                .foregroundStyle(Theme.onWarm)
                .padding(16).background(Theme.warm, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("每日目标 \(goalMinutes) 分钟，已读 \(Int(today / 60)) 分钟")
            .accessibilityHint("轻点调整每日目标")
        }
    }

    private func saveGoal() {
        goalMinutes = goalDraft
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        reminderMinutes = (comps.hour ?? 21) * 60 + (comps.minute ?? 0)
        reminderEnabled = reminderDraft
        let (enabled, minutes, goal) = (reminderDraft, reminderMinutes, goalDraft)
        let today = model.readingSeconds[AppModel.dayKey(Date())] ?? 0
        Task {
            let granted = await ReadingReminder.reschedule(enabled: enabled, minutes: minutes, goalMinutes: goal, todaySeconds: today)
            if enabled && !granted { reminderDenied = true; reminderEnabled = false; reminderDraft = false }
            else { reminderDenied = false; editingGoal = false }
        }
        if !enabled { editingGoal = false }
    }

    private var goalEditor: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goalDraft, in: 5...600, step: 5) {
                        HStack { Text("每日目标"); Spacer(); Text("\(goalDraft) 分钟").monospacedDigit().foregroundStyle(Theme.ink3) }
                    }
                } footer: { Text("阅读和听书的时间都会计入。") }
                .listRowBackground(Theme.surface)
                Section {
                    Toggle("每日阅读提醒", isOn: $reminderDraft.animation())
                        .tint(Theme.clay)
                        .accessibilityIdentifier("goal.reminder")
                    if reminderDraft {
                        DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(reminderDenied ? "通知权限未开启，请在系统设置 › 通知 › 听页中允许。" : "当天读够目标就不再提醒。提醒只在本机生成。")
                        .foregroundStyle(reminderDenied ? Theme.danger : Theme.ink3)
                }
                .listRowBackground(Theme.surface)
                Section("常用") {
                    ForEach([15, 30, 60, 120], id: \.self) { value in
                        Button { goalDraft = value } label: {
                            HStack { Text("\(value) 分钟").foregroundStyle(Theme.ink); Spacer(); if goalDraft == value { Image(systemName: Icon.checkmark).foregroundStyle(Theme.accent) } }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("阅读目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { editingGoal = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveGoal() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: 图表

    private var chart: some View {
        let unit: Calendar.Component = period == .year || period == .all ? .month : .day
        let displayed = period == .day ? calendar.dateInterval(of: .weekOfYear, for: interval.start) ?? interval : interval
        let totals = model.readingSeconds.compactMap { key, seconds in Self.date(fromKey: key).map { (date: $0, seconds: seconds) } }
            .filter { displayed.contains($0.date) }
        let points: [(date: Date, minutes: Double)] = {
            var grouped: [Date: Double] = [:]
            for item in totals {
                let bucket = calendar.dateInterval(of: unit, for: item.date)?.start ?? item.date
                grouped[bucket, default: 0] += item.seconds / 60
            }
            var values: [(date: Date, minutes: Double)] = []
            var date = calendar.dateInterval(of: unit, for: displayed.start)?.start ?? displayed.start
            while date < displayed.end {
                values.append((date, grouped[date] ?? 0))
                guard let next = calendar.date(byAdding: unit, value: 1, to: date), next > date else { break }
                date = next
            }
            return values
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                Text("阅读节奏").font(.caption.weight(.medium)).foregroundStyle(Theme.ink2)
                Text(period == .day ? (offset == 0 ? "本周 · 分钟" : "所在周 · 分钟") : unit == .day ? "分钟 / 天" : "分钟 / 月")
                    .font(.caption2).foregroundStyle(Theme.ink2)
                    .fixedSize()
            }
            Chart(points, id: \.date) { point in
                BarMark(x: .value("日期", point.date, unit: unit), y: .value("分钟", point.minutes))
                    .foregroundStyle(calendar.isDate(point.date, inSameDayAs: period == .day ? interval.start : Date()) ? Theme.accent : Theme.accentSoft)
                    .cornerRadius(8)
            }
            .chartXScale(domain: displayed.start...displayed.end)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel().foregroundStyle(Theme.ink2)
            } }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.ink2) } }
            .frame(height: 150)
            .overlay {
                if points.allSatisfy({ $0.minutes == 0 }) {
                    Text("这段时间没有阅读记录").font(.footnote).foregroundStyle(Theme.ink2)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 阅读时段

    @ViewBuilder
    private var sessionsCard: some View {
        let list = periodSessions.sorted { $0.start > $1.start }
        if period == .day || period == .week {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("逐次记录").scaledFont(20, weight: .bold, relativeTo: .title3)
                    Spacer()
                    Button("查看日历") { showingCalendar = true }
                        .font(.caption).frame(minHeight: 44)
                        .accessibilityIdentifier("stats.calendar")
                }.padding(.bottom, 6)
                if list.isEmpty {
                    Label("开始阅读或听书后，这里会留下记录。", systemImage: Icon.duration)
                        .font(.footnote).foregroundStyle(Theme.ink2)
                        .padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(list.prefix(30))) { session in
                        let entry = model.entries.first { $0.id == session.bookID }
                        HStack(spacing: 12) {
                            ThemeIcon(symbol: session.listening ? Icon.listen : Icon.read, size: 24)
                                .foregroundStyle(Theme.ink).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                                Text((session.listening ? "听书 " : "阅读 ") + "\(max(1, Int(session.seconds / 60))) 分钟 · " + timeRange(session))
                                    .font(.caption).monospacedDigit().foregroundStyle(Theme.ink2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if let entry {
                                Text(entry.percentText).font(.caption).monospacedDigit().foregroundStyle(Theme.accent)
                                    .accessibilityLabel("全书进度 " + entry.percentText)
                            }
                        }
                        .padding(.vertical, 12).frame(minHeight: 64)
                        .overlay(alignment: .bottom) { RowDivider() }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func timeRange(_ session: ReadingSession) -> String {
        let f = DateFormatter(); f.dateFormat = period == .day ? "HH:mm" : "M/d HH:mm"
        let g = DateFormatter(); g.dateFormat = "HH:mm"
        return f.string(from: session.start) + " – " + g.string(from: session.end)
    }

    // MARK: 排行

    @ViewBuilder
    private var ranking: some View {
        var totals: [String: (title: String, seconds: Double)] = [:]
        let _ = periodSessions.forEach { totals[$0.bookID, default: ($0.title, 0)].seconds += $0.seconds }
        let rows = totals.sorted { $0.value.seconds > $1.value.seconds }.prefix(10)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "与这些书相伴")
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                        let entry = model.entries.first { $0.id == row.key }
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1)).font(Theme.display(28)).monospacedDigit()
                                .foregroundStyle(index == 0 ? Theme.accent : Theme.ink).frame(width: 34, alignment: .leading)
                            BookCoverView(title: entry?.title ?? row.value.title, color: entry?.color ?? "gray", image: model.covers[row.key], width: 34)
                            Text(entry?.title ?? row.value.title).font(Theme.serif(15).weight(.medium)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Self.durationText(row.value.seconds)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink2)
                        }
                        .frame(minHeight: 72)
                        RowDivider()
                    }
                }
            }
        }
    }

    // MARK: 工具

    static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds)
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }
    static func durationNumber(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 600 ? String(format: "%.1f", Double(minutes) / 60) : "\(minutes)"
    }
    static func durationUnit(_ seconds: Double) -> String { L(Int(seconds / 60) >= 600 ? "小时" : "分钟") }
    static func durationText(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(max(1, minutes)) 分钟"
    }

    private func exportStats() {
        do {
            let payload = ReadingStatsExport(exportedAt: Date(), readingSeconds: model.readingSeconds, entries: model.visibleEntries.map { .init(id: $0.id, title: $0.title, author: $0.author, chapterCount: $0.chapterCount, percent: $0.percentText, progress: $0.progress) }, sessions: model.visibleSessions)
            let encoder = Integrity.encoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tingye-reading-stats.json")
            try encoder.encode(payload).write(to: url, options: .atomic)
            export = ExportedBook(url: url)
        } catch { model.message = error.localizedDescription }
    }
}

/// 设置目录独立持有下一层路由，返回外观或阅读排版时仍停留在目录。
/// 不能复用「我的」的 destination state，否则 SwiftUI 会替换设置目录这一层。
private struct SettingsDirectoryView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("app.appearance") private var appearance = "system"
    @State private var settingsRoute: SettingsDestination?
    @State private var showingImportHub = false
    @State private var importingBooks = false

    private var appearanceName: String { ["system": "跟随系统", "light": "日间", "dark": "夜间"][appearance] ?? "跟随系统" }

    var body: some View {
        List {
            Section {
                settingsEntry(icon: Icon.typography, title: "阅读排版", subtitle: "字号、行距、纸色与翻页方式") { settingsRoute = .reading }
                    .accessibilityIdentifier("profile.reading")
                settingsEntry(icon: Icon.fonts, title: "字体管理", subtitle: "查看与导入自己的字体") { settingsRoute = .fonts }
                settingsEntry(icon: Icon.list, title: "菜单", subtitle: "选中文字后的操作顺序与显示") { settingsRoute = .menu }
                    .accessibilityIdentifier("profile.menu")
                settingsEntry(icon: Icon.contents, title: "TXT 分章规则", subtitle: "自定义规则与章节最大字数") { settingsRoute = .txtRules }
                    .accessibilityIdentifier("profile.txtRules")
            } header: { Text("阅读") }
            .listRowBackground(Theme.surface)
            Section {
                settingsEntry(icon: Icon.voice, title: "声音与朗读", value: model.player.voiceLabel) { settingsRoute = .voice }
            } header: { Text("听书与声音") }
            .listRowBackground(Theme.surface)
            Section {
                settingsEntry(icon: Icon.discover, title: "传书与导入", subtitle: "WiFi 传书、WebDAV 与 OPDS") { showingImportHub = true }
            } header: { Text("书库与导入") }
            .listRowBackground(Theme.surface)
            Section {
                settingsEntry(icon: Icon.cloud, title: "备份与同步", subtitle: "书库备份与阅读进度同步") { settingsRoute = .backup }
                    .accessibilityIdentifier("profile.backup")
                settingsEntry(icon: Icon.server, title: "空间整理", subtitle: "查看占用、清理缓存与修复索引") { settingsRoute = .storage }
                    .accessibilityIdentifier("profile.storage")
            } header: { Text("数据与备份") }
            .listRowBackground(Theme.surface)
            Section {
                settingsEntry(icon: Icon.appearance, title: "外观", value: appearanceName) { settingsRoute = .appearance }
                    .accessibilityIdentifier("profile.appearance")
                settingsEntry(icon: Icon.settings, title: "通用设置", subtitle: "启动续读、目标提示、震动反馈") { settingsRoute = .general }
                    .accessibilityIdentifier("profile.general")
                settingsEntry(icon: Icon.settings, title: "隐私与关于", subtitle: "应用锁、隐藏书籍、隐私与版本") { settingsRoute = .profile }
            } header: { Text("通用") } footer: { Text("听页 · 书籍保存在本机") }
            .listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden)
        .background(Theme.bg).tint(Theme.accent)
        .navigationTitle("设置").navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $settingsRoute) { route in
            settingsDestinationView(route)
                .toolbar(.visible, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        }
        .sheet(isPresented: $showingImportHub, onDismiss: {
            // 与书库页同口径：ImportHub 内登记的文件导入请求在面板关闭后从本层打开选择器。
            if model.consumeFileImportRequest() { importingBooks = true }
        }) {
            ImportHubView().environmentObject(model).tint(Theme.accent)
        }
        .bookImporter(isPresented: $importingBooks)
    }

    private func settingsEntry(icon: String, title: String, subtitle: String? = nil, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(title)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    if let subtitle { Text(L(subtitle)).font(.caption).foregroundStyle(Theme.ink3) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value { Text(L(value)).font(.caption).foregroundStyle(Theme.ink3).lineLimit(1) }
                ThemeIcon(symbol: Icon.disclosure, size: 16).foregroundStyle(Theme.ink3)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressButtonStyle(scale: 0.99))
    }

}

/// 图例标签：方块与文字紧贴。
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon; configuration.title }
    }
}

// MARK: - 每日阅读提醒

/// 本地每日提醒：排未来 7 天的单次通知（不用重复触发器），这样当天读够目标后能只撤掉当天那条。
/// App 回到前台或进入后台时重排，提醒内容只用本地数据，不联网。
enum ReadingReminder {
    static let enabledKey = "reminder.enabled"
    static let minutesKey = "reminder.minutes"
    static let defaultMinutes = 21 * 60
    private static let prefix = "tingye.reminder."

    /// 计划的提醒时刻：今天的时刻已过或今天已达标则从明天开始，共 `days` 条。
    static func plannedDates(now: Date, minutes: Int, todayMet: Bool, days: Int = 7, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: now)
        return (0..<(days + 1)).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let fire = calendar.date(byAdding: .minute, value: minutes, to: day) else { return nil }
            if offset == 0 && (todayMet || fire <= now) { return nil }
            return fire
        }
        .prefix(days).map { $0 }
    }

    /// 重排提醒；关闭时只清除。返回是否已获得通知权限。
    @discardableResult @MainActor
    static func reschedule(enabled: Bool, minutes: Int, goalMinutes: Int, todaySeconds: Double, now: Date = Date()) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let calendar = Calendar.current
        for date in plannedDates(now: now, minutes: minutes, todayMet: todaySeconds >= Double(goalMinutes * 60), calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = "今天读一页？"
            content.body = "离 \(goalMinutes) 分钟的阅读目标还差一点。翻开书，或者合上眼睛听一段。"
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let request = UNNotificationRequest(identifier: prefix + AppModel.dayKey(date),
                                                content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
        return true
    }

    /// 用当前设置与今日时长重排，供 App 前后台切换时调用。
    @MainActor static func refresh(model: AppModel) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return }
        let minutes = defaults.object(forKey: minutesKey) as? Int ?? defaultMinutes
        let goal = defaults.object(forKey: "goal.dailyMinutes") as? Int ?? 30
        let today = model.readingSeconds[AppModel.dayKey(Date())] ?? 0
        Task { await reschedule(enabled: true, minutes: minutes, goalMinutes: goal, todaySeconds: today) }
    }
}
