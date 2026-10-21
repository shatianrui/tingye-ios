import SwiftUI
import Charts

/// 统计（参照 PureLibro）：日 / 周 / 月 / 年 / 总；概览数字、阅读目标、时长图表、阅读时段、按书排行。
/// 按日的总时长来自 `readingSeconds`（旧版本也有）；时段与排行来自 1.14 起记录的 `sessions`。
struct StatsView: View {
    @EnvironmentObject var model: AppModel
    /// v16「墨」：己页签 = 统计 + 今日摘句 + 设置题录清单；从设置页进入的纯统计为 false。
    var ji = false
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @AppStorage("app.appearance") private var appearance = "system"
    @State private var period: Period = .day
    @State private var offset = 0
    @State private var editingGoal = false
    @State private var goalDraft = 30
    @State private var export: ExportedBook?
    @State private var settingsRoute: SettingsDestination?
    @State private var showingImportHub = false
    @ScaledMetric(relativeTo: .largeTitle) private var durationSize = 44
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 8) {
                    PageMasthead(title: ji ? "己" : "足迹", subtitle: ji ? "读过的书，和这台设备上的书。" : "阅读和听书的时间。")
                    Button("目标") { editGoal() }
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                    Menu {
                        Button { exportStats() } label: { Label("导出全部阅读数据", systemImage: Icon.share) }
                    } label: {
                        ThemeIcon(symbol: Icon.more, size: 22).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("更多阅读数据操作")
                }
                .font(.subheadline).foregroundStyle(Theme.ink2)
                HStack(spacing: 0) {
                    ForEach(Period.allCases) { item in
                        Button { period = item } label: {
                            Text(item.rawValue).font(.subheadline.weight(period == item ? .semibold : .regular))
                                .foregroundStyle(period == item ? Theme.accent : Theme.ink3)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(period == item ? Theme.accentSoft : .clear, in: Capsule())
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(period == item ? .isSelected : [])
                        .accessibilityLabel("按" + item.rawValue + "查看")
                    }
                }
                .onChange(of: period) { _, _ in offset = 0 }
                if period != .all { periodNavigation }
                header
                chart
                if period == .day && offset == 0 { goalCard }
                sessionsCard
                ranking
                overview
                if period == .day && offset == 0 { DailyQuoteCard() }
                if ji { settingsSection }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationTitle(ji ? "己" : "足迹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $settingsRoute) { route in
            settingsDestinationView(route)
                .toolbar(.visible, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        }
        .sheet(isPresented: $showingImportHub) { ImportHubView().environmentObject(model).tint(Theme.accent) }
        #if DEBUG
        .task {
            if let screen = UIReview.screen, settingsRoute == nil {
                if screen == "appearance" { settingsRoute = .appearance }
                else if screen == "backup" { settingsRoute = .backup }
                else if screen == "profile" { settingsRoute = .profile }
            }
        }
        #endif
        #if DEBUG
        .task { if UIReview.screen == "stats-goal" { editGoal() } }
        #endif
        .sheet(isPresented: $editingGoal) { goalEditor }
        .sheet(item: $export) { ShareSheet(items: [$0.url]) }
    }

    // MARK: 头部：总时长 + 区间与前后切换

    private var header: some View {
        let reading = periodSessions.filter { !$0.listening }.reduce(0) { $0 + $1.seconds }
        let listening = periodSessions.filter(\.listening).reduce(0) { $0 + $1.seconds }
        let unclassified = max(0, totalSeconds - reading - listening)
        return VStack(alignment: .leading, spacing: 6) {
            Text(period == .day && offset == 0 ? "今天 · 慢慢读" : "留给阅读的时间")
                .font(Theme.kicker).tracking(1.2).foregroundStyle(Theme.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.durationNumber(totalSeconds))
                    .font(Theme.display(durationSize)).monospacedDigit()
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(Self.durationUnit(totalSeconds)).font(.body).foregroundStyle(Theme.ink2)
            }
            .foregroundStyle(Theme.ink).accessibilityElement(children: .combine)
            summaryLayout {
                Label { Text("阅读 \(Int(reading / 60)) 分钟") } icon: { Rectangle().fill(Theme.ink).frame(width: 9, height: 9) }
                    .foregroundStyle(Theme.ink)
                Label { Text("听书 \(Int(listening / 60)) 分钟") } icon: { Rectangle().fill(Theme.accent).frame(width: 9, height: 9) }
                    .foregroundStyle(Theme.accent)
            }
            .font(.subheadline)
            .labelStyle(TightLabelStyle())
            if unclassified >= 60 {
                Text("另有 \(Int(unclassified / 60)) 分钟旧版记录未区分阅读与听书")
                    .font(.caption2).foregroundStyle(Theme.ink2)
            }
            if period == .all { Text(intervalLabel).font(.caption).foregroundStyle(Theme.ink2) }
        }
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
        editingGoal = true
    }

    private var intervalLabel: String {
        let i = interval
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        switch period {
        case .day: f.dateFormat = "yyyy 年 M 月 d 日 EEEE"; return f.string(from: i.start)
        case .week:
            f.dateFormat = "M 月 d 日"
            return f.string(from: i.start) + " – " + f.string(from: i.end.addingTimeInterval(-1))
        case .month: f.dateFormat = "yyyy 年 M 月"; return f.string(from: i.start)
        case .year: f.dateFormat = "yyyy 年"; return f.string(from: i.start)
        case .all:
            f.dateFormat = "yyyy 年 M 月 d 日"
            return "自 " + f.string(from: i.start) + " 起 · \(dayTotals.filter { $0.seconds > 0 }.count) 天"
        }
    }

    // MARK: 概览

    private var overview: some View {
        let ids = Set(periodSessions.map(\.bookID))
        let finished = model.entries.filter { $0.started && $0.readFraction >= 0.995 }.count
        return VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "阅读足迹", number: "05")
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
            }
        }
    }

    private func metric(_ title: String, _ value: Int, _ unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) { ThemeIcon(symbol: icon, size: 16); Text(title) }
                .font(.caption)
                .foregroundStyle(Theme.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(value)").scaledFont(28, weight: .medium, relativeTo: .title2).monospacedDigit().foregroundStyle(Theme.ink)
                Text(unit).font(.caption).foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: 阅读目标

    private var goalCard: some View {
        let today = model.readingSeconds[AppModel.dayKey(Date())] ?? 0
        let fraction = min(1, today / Double(max(1, goalMinutes) * 60))
        let remaining = max(0, goalMinutes - Int(today / 60))
        return Button { editGoal() } label: {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "每日目标", number: "02")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(today / 60))").scaledFont(30, weight: .medium, relativeTo: .title2).monospacedDigit()
                    Text("/ \(goalMinutes) 分钟").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink2)
                    Spacer(minLength: 4)
                    Text(fraction >= 1 ? "已完成 ✓" : "还差 \(remaining) 分钟")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(fraction >= 1 ? Theme.accent : Theme.ink2)
                }
                .foregroundStyle(Theme.ink)
                ProgressBar(value: fraction, tint: Theme.accent, height: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("每日目标 \(goalMinutes) 分钟，已读 \(Int(today / 60)) 分钟")
        .accessibilityHint("轻点调整每日目标")
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
                    Button("保存") { goalMinutes = goalDraft; editingGoal = false }.fontWeight(.semibold)
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
                SectionTitle(title: "阅读节奏", number: "01")
                Text(period == .day ? (offset == 0 ? "本周 · 分钟" : "所在周 · 分钟") : unit == .day ? "分钟 / 天" : "分钟 / 月")
                    .font(.caption2).foregroundStyle(Theme.ink2)
                    .fixedSize()
            }
            Chart(points, id: \.date) { point in
                BarMark(x: .value("日期", point.date, unit: unit), y: .value("分钟", point.minutes))
                    .foregroundStyle(calendar.isDate(point.date, inSameDayAs: period == .day ? interval.start : Date()) ? Theme.accent : Theme.ink)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 阅读时段

    @ViewBuilder
    private var sessionsCard: some View {
        let list = periodSessions.sorted { $0.start > $1.start }
        if period == .day || period == .week {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(title: "逐次记录", number: "03").padding(.bottom, 6)
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
                SectionTitle(title: "与这些书相伴", number: "04")
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

    // MARK: 己 · 设置题录清单

    private var appearanceName: String { ["system": "跟随系统", "light": "日间", "dark": "夜间"][appearance] ?? "跟随系统" }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RowDivider()
            Text("设置")
                .font(Theme.serifSemibold(22, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            settingsEntry(icon: Icon.typography, title: "阅读排版", subtitle: "字号、行距、纸色与翻页方式") { settingsRoute = .reading }
            settingsEntry(icon: Icon.fonts, title: "字体管理", subtitle: "查看与导入自己的字体") { settingsRoute = .fonts }
            settingsEntry(icon: Icon.voice, title: "声音与朗读", subtitle: "语音服务、音色与朗读设置") { settingsRoute = .voice }
            settingsEntry(icon: Icon.appearance, title: "外观模式", value: appearanceName) { settingsRoute = .appearance }
            settingsEntry(icon: Icon.discover, title: "传书与导入", subtitle: "WiFi 传书、WebDAV 与 OPDS") { showingImportHub = true }
            settingsEntry(icon: Icon.cloud, title: "备份与同步", subtitle: "书库备份与阅读进度同步") { settingsRoute = .backup }
            settingsEntry(icon: Icon.highlight, title: "全部书摘与笔记", value: "\(model.noteCount) 条") { settingsRoute = .notes }
            settingsEntry(icon: Icon.settings, title: "更多设置", subtitle: "应用锁、隐藏书籍、隐私与关于") { settingsRoute = .profile }
        }
        .padding(.top, 8)
    }

    private func settingsEntry(icon: String, title: String, subtitle: String? = nil, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ThemeIcon(symbol: icon, size: 22, weight: .medium)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.ink3) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value { Text(value).font(.caption).foregroundStyle(Theme.ink3).lineLimit(1) }
                ThemeIcon(symbol: Icon.disclosure, size: 16).foregroundStyle(Theme.ink3)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressButtonStyle(scale: 0.99))
        .overlay(alignment: .bottom) { RowDivider() }
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
    static func durationUnit(_ seconds: Double) -> String { Int(seconds / 60) >= 600 ? "小时" : "分钟" }
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

/// 图例标签：方块与文字紧贴。
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon; configuration.title }
    }
}
