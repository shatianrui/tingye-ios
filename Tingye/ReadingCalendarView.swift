import SwiftUI

/// 阅读日历：按月查看每天的阅读 / 听书时长，陶土淡底表示读日，达到每日目标的日子加粗下划线。
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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space5) {
                    Masthead(title: "阅读日历", subtitle: "选择一天，看看那天读过的书。", titleSize: 28)
                    header
                    ScrollView(.horizontal) {
                        VStack(spacing: Theme.space3) { weekdayRow; grid }.frame(minWidth: 332)
                    }.paperPanel(inset: Theme.space3)
                    dayDetail
                    monthSummary
                }
                .padding(.horizontal, Theme.inset).padding(.vertical, Theme.space4)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .paperBackground()
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
                .font(Theme.serif(24, relativeTo: .title2))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { shift(1) } label: { ThemeIcon(symbol: Icon.disclosure, size: 18).frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize) }
                .accessibilityLabel("下个月")
                .disabled(isCurrentMonth).opacity(isCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(Theme.ink)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaySymbols(calendar), id: \.self) { day in
                Text(day).font(Theme.sans(13)).foregroundStyle(Theme.ink3).frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.space1), count: 7), spacing: Theme.space1) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date { dayCell(date) } else { Color.clear.frame(height: Theme.space7) }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let minutes = Self.minutes(model.readingSeconds, on: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let future = date > Date()
        let today = calendar.isDateInToday(date)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button { selected = date } label: {
            VStack(spacing: Theme.space1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(Theme.sans(15, weight: today || isSelected ? .medium : .regular)).monospacedDigit()
                Circle().fill(minutes >= goalMinutes ? Theme.clay : .clear).frame(width: 4, height: 4)
            }
            .foregroundStyle(future ? Theme.ink4 : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.space7)
            .background(minutes > 0 ? Theme.claySoft : .clear, in: shape)
            .overlay { if today { shape.strokeBorder(Theme.clay, lineWidth: Theme.ruleMedium) } }
            .overlay { if isSelected { shape.strokeBorder(Theme.ink, lineWidth: Theme.ruleMedium) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel((today ? "今天，" : "") + date.formatted(.dateTime.month().day().locale(Locale.app)) + "，\(minutes) 分钟")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayDetail: some View {
        let minutes = Self.minutes(model.readingSeconds, on: selected)
        let sessions = model.visibleSessions.filter { calendar.isDate($0.start, inSameDayAs: selected) }
        let books = Dictionary(grouping: sessions, by: \.title).map { ($0.key, $0.value.reduce(0) { $0 + $1.seconds }) }.sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: Theme.space2) {
            Text(selected.formatted(.dateTime.month().day().weekday(.wide).locale(Locale.app)))
                .font(Theme.sans(13)).tracking(0.6).foregroundStyle(Theme.clayDeep)
            HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
                Text("\(minutes)").font(Theme.serif(40, relativeTo: .largeTitle)).monospacedDigit()
                Text("分钟").font(.subheadline).foregroundStyle(Theme.ink2)
                Spacer()
                if minutes >= goalMinutes { Text("达成目标").font(Theme.sans(13)).foregroundStyle(Theme.clayDeep) }
            }
            if books.isEmpty && minutes == 0 {
                EmptyState(title: "这一天还没有阅读记录。", detail: "选择一天，看看那天读过的书。")
            }
            ForEach(books, id: \.0) { title, seconds in
                HairlineRow {
                    HStack {
                        Text(title.isEmpty ? "未命名" : "《\(title)》").font(Theme.serif(17)).lineLimit(1)
                        Spacer()
                        Text("\(max(1, Int(seconds / 60))) 分").font(.footnote).monospacedDigit().foregroundStyle(Theme.ink2)
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
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
        }.paperPanel()
    }

    private func summary(_ value: String, _ label: String) -> some View {
        StatBlock(value: value, label: label)
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
