import SwiftUI

/// 阅读日历：按月查看每天的阅读 / 听书时长，强调色淡底表示读日，达到每日目标的日子加粗下划线。
struct ReadingCalendarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.themeDirection) private var themeDirection
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selected = Calendar.current.startOfDay(for: Date())
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    var body: some View {
        let clear = themeDirection == .systemClear
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space4) {
                    if !clear {
                        Masthead(title: "阅读日历", subtitle: "选择一天，看看那天读过的书。", rule: false, titleSize: 26)
                    }
                    VStack(spacing: Theme.space3) {
                        header
                        weekdayRow
                        grid
                    }
                    .padding(Theme.cardInset)
                    .background(Theme.sheetCard, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .strokeBorder(clear ? Theme.line.opacity(0.22) : Theme.line, lineWidth: Theme.hairline)
                    }
                    dayDetail
                    monthSummary
                }
                .padding(.horizontal, Theme.insetCompact).padding(.vertical, Theme.space4)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .groupedBackground()
            .sheetSurface()
            .navigationTitle("阅读日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { ThemeIcon(symbol: Icon.back, size: 17).frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize) }
                .accessibilityLabel("上个月")
            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide).locale(Locale.app)))
                .font(Theme.heading(20, relativeTo: .title3))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { shift(1) } label: { ThemeIcon(symbol: Icon.disclosure, size: 17).frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize) }
                .accessibilityLabel("下个月")
                .disabled(isCurrentMonth).opacity(isCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(Theme.ink)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaySymbols(calendar), id: \.self) { day in
                Text(day).font(.caption.weight(.medium)).foregroundStyle(Theme.ink3).frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        let clear = themeDirection == .systemClear
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: clear ? 4 : 0), count: 7), spacing: clear ? 4 : 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear
                        .frame(height: 44)
                        .overlay {
                            if !clear { Rectangle().strokeBorder(Theme.line, lineWidth: Theme.hairline) }
                        }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let clear = themeDirection == .systemClear
        let minutes = Self.minutes(model.readingSeconds, on: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let future = date > Date()
        let today = calendar.isDateInToday(date)
        return Button { selected = date } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(today || isSelected ? .semibold : .regular)).monospacedDigit()
                Capsule()
                    .fill(minutes >= goalMinutes ? (clear ? Theme.accent : Theme.ink) : .clear)
                    .frame(width: 12, height: 2.5)
            }
            .foregroundStyle(future ? Theme.ink4 : (isSelected && clear ? Theme.accent : Theme.ink))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(minutes > 0 ? Theme.claySoft : .clear, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay {
                if !clear { Rectangle().strokeBorder(Theme.line, lineWidth: Theme.hairline) }
            }
            .overlay {
                if today {
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.clay, lineWidth: 1.5)
                } else if isSelected {
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(clear ? Theme.accent : Theme.ink2, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel((today ? "今天，" : "") + date.formatted(.dateTime.month().day().locale(Locale.app)) + "，\(minutes) 分钟")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayDetail: some View {
        let clear = themeDirection == .systemClear
        let minutes = Self.minutes(model.readingSeconds, on: selected)
        let sessions = model.visibleSessions.filter { calendar.isDate($0.start, inSameDayAs: selected) }
        let books = Dictionary(grouping: sessions, by: \.title).map { ($0.key, $0.value.reduce(0) { $0 + $1.seconds }) }.sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: Theme.space2) {
            Text(selected.formatted(.dateTime.month().day().weekday(.wide).locale(Locale.app)))
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.clayDeep)
            HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
                Text("\(minutes)").font(Theme.display(34, relativeTo: .largeTitle)).monospacedDigit()
                Text("分钟").font(.subheadline).foregroundStyle(Theme.ink2)
                Spacer()
                if minutes >= goalMinutes { SealBadge(text: "达成目标") }
            }
            if books.isEmpty && minutes == 0 {
                Text("这一天还没有阅读记录。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 4)
            }
            ForEach(Array(books.enumerated()), id: \.element.0) { index, pair in
                HairlineRow(showsDivider: index < books.count - 1) {
                    HStack {
                        Text(pair.0.isEmpty ? "未命名" : "《\(pair.0)》").font(clear ? .subheadline.weight(.medium) : Theme.serif(17)).lineLimit(1)
                        Spacer()
                        Text("\(max(1, Int(pair.1 / 60))) 分钟").font(.footnote).monospacedDigit().foregroundStyle(Theme.ink2)
                    }
                }
            }
        }
        .padding(Theme.cardInset)
        .background(Theme.sheetCard, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(clear ? Theme.line.opacity(0.22) : Theme.line, lineWidth: Theme.hairline)
        }
        .foregroundStyle(Theme.ink)
    }

    private var monthSummary: some View {
        let clear = themeDirection == .systemClear
        let monthDays = days.compactMap { $0 }
        let read = monthDays.filter { Self.minutes(model.readingSeconds, on: $0) >= 1 }.count
        let reached = monthDays.filter { Self.minutes(model.readingSeconds, on: $0) >= goalMinutes }.count
        let total = monthDays.reduce(0) { $0 + Self.minutes(model.readingSeconds, on: $1) }
        return (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space4)) : AnyLayout(HStackLayout(spacing: Theme.space5))) {
            summary("\(read)", "阅读天数")
            summary("\(reached)", "达标天数")
            summary("\(total)", "本月分钟")
        }
        .padding(Theme.cardInset)
        .background(Theme.sheetCard, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(clear ? Theme.line.opacity(0.22) : Theme.line, lineWidth: Theme.hairline)
        }
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
