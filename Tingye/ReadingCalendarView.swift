import SwiftUI

/// 阅读日历：按月查看读听时长，标示读过、今日、选中与达标。
struct ReadingCalendarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selected = Calendar.current.startOfDay(for: Date())
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    var body: some View {
        NavigationStack {
            IndexPage {
                SettingsGroup {
                    header
                    ScrollView(.horizontal) {
                        VStack(spacing: Theme.space2) { weekdayRow; grid }.frame(minWidth: 332)
                    }
                    .padding(.vertical, Theme.space2)
                }
                SettingsGroup {
                    dayDetail
                }
                SettingsGroup(title: "本月记录") {
                    monthSummary
                }
            }
            .tint(IndexTheme.accent)
            .navigationTitle("阅读日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { ThemeIcon(symbol: Icon.back, size: 18).frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize) }
                .accessibilityLabel("上个月")
            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide).locale(Locale.app)))
                .font(IndexTheme.editorial(24, relativeTo: .title2))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { shift(1) } label: { ThemeIcon(symbol: Icon.disclosure, size: 18).frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize) }
                .accessibilityLabel("下个月")
                .disabled(isCurrentMonth).opacity(isCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(IndexTheme.ink)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaySymbols(calendar), id: \.self) { day in
                Text(day).font(Theme.sans(13)).foregroundStyle(IndexTheme.muted).frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date { dayCell(date) } else { Color.clear.frame(height: Theme.space7).overlay { Rectangle().strokeBorder(IndexTheme.rule, lineWidth: Theme.hairline) } }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let minutes = Self.minutes(model.readingSeconds, on: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let future = date > Date()
        let today = calendar.isDateInToday(date)
        return Button { selected = date } label: {
            VStack(spacing: Theme.space1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(Theme.sans(15)).monospacedDigit()
                Rectangle().fill(minutes >= goalMinutes ? IndexTheme.ink : .clear).frame(width: Theme.space3, height: Theme.ruleMedium)
            }
            .foregroundStyle(future ? IndexTheme.muted : IndexTheme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.space7)
            .background(minutes > 0 ? IndexTheme.wash : .clear, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay { Rectangle().strokeBorder(IndexTheme.rule, lineWidth: Theme.hairline) }
            .overlay { if today { Circle().strokeBorder(IndexTheme.accent, lineWidth: Theme.rule).padding(Theme.space1) } }
            .overlay { if isSelected { RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(IndexTheme.ink, lineWidth: Theme.rule) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(today
            ? Text("今天，\(date.formatted(.dateTime.month().day().locale(.app)))")
            : Text(verbatim: date.formatted(.dateTime.month().day().locale(.app))))
        .accessibilityValue(minutes >= goalMinutes ? Text("\(minutes) 分钟，达成目标") : Text("\(minutes) 分钟"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayDetail: some View {
        let minutes = Self.minutes(model.readingSeconds, on: selected)
        let sessions = model.visibleSessions.filter { calendar.isDate($0.start, inSameDayAs: selected) }
        let books = Dictionary(grouping: sessions, by: \.title).map { ($0.key, $0.value.reduce(0) { $0 + $1.seconds }) }.sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: Theme.space2) {
            Text(selected.formatted(.dateTime.month().day().weekday(.wide).locale(Locale.app)))
                .font(Theme.sans(13)).tracking(0.6).foregroundStyle(IndexTheme.accent)
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space1))
                                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.space3))) {
                Text("\(minutes) 分钟").font(IndexTheme.editorial(32, relativeTo: .largeTitle)).monospacedDigit()
                if minutes >= goalMinutes { Text("达成目标").font(.caption).foregroundStyle(IndexTheme.accent) }
            }
            if books.isEmpty && minutes == 0 {
                IndexStatus(kind: .empty, title: Text("这一天还没有阅读记录。"))
            }
            ForEach(books, id: \.0) { title, seconds in
                HairlineRow {
                    HStack {
                        (title.isEmpty ? Text("未命名") : Text(verbatim: title)).font(IndexTheme.editorial(17, relativeTo: .body))
                        Spacer()
                        Text("\(max(1, Int(seconds / 60))) 分").font(.footnote).monospacedDigit().foregroundStyle(IndexTheme.ink)
                    }
                }
            }
        }
        .foregroundStyle(IndexTheme.ink)
    }

    private var monthSummary: some View {
        let monthDays = days.compactMap { $0 }
        let read = monthDays.filter { Self.minutes(model.readingSeconds, on: $0) >= 1 }.count
        let reached = monthDays.filter { Self.minutes(model.readingSeconds, on: $0) >= goalMinutes }.count
        let total = monthDays.reduce(0) { $0 + Self.minutes(model.readingSeconds, on: $1) }
        return (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space4)) : AnyLayout(HStackLayout(spacing: Theme.space5))) {
            summary("\(read)", "阅读天数")
            summary("\(reached)", "达标天数")
            summary("\(total)", "本月分钟")
        }
    }

    private func summary(_ value: String, _ label: String) -> some View {
        IndexMetric(value: Text(verbatim: value), label: Text(L(label)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: 数据

    private var isCurrentMonth: Bool { calendar.isDate(month, equalTo: Date(), toGranularity: .month) }
    private func shift(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month), next <= Date() else { return }
        month = next
        selected = isCurrentMonth ? calendar.startOfDay(for: Date()) : next
    }
    /// 当月所有日期，前面用 nil 补齐到周一开头。
    private var days: [Date?] { Self.monthDays(month, calendar: calendar) }
    static func monthDays(_ month: Date, calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }
    /// 按界面语言给出周一开头的星期简称。
    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        var c = calendar; c.locale = .app
        let symbols = c.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...] + symbols[..<1])
    }
    static func minutes(_ seconds: [String: Double], on date: Date) -> Int { Int((seconds[AppModel.dayKey(date)] ?? 0) / 60) }
    /// 色块深浅：最少 0.25，达到目标为 1。
    static func intensity(minutes: Int, goal: Int) -> Double { min(1, 0.25 + 0.75 * Double(minutes) / Double(max(1, goal))) }
}
