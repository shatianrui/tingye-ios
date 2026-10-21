import SwiftUI

/// 阅读日历：按月查看每天的阅读 / 听书时长，陶土色深浅表示时长，达到每日目标的日子加粗下划线。
struct ReadingCalendarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selected = Calendar.current.startOfDay(for: Date())
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    weekdayRow
                    grid
                    Rectangle().fill(Theme.rulePaint).frame(height: Theme.ruleMedium)
                    dayDetail
                    monthSummary
                }
                .padding(.horizontal, Theme.inset).padding(.vertical, 16)
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
            Button { shift(-1) } label: { ThemeIcon(symbol: Icon.back, size: 18).frame(width: 44, height: 44) }
                .accessibilityLabel("上个月")
            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide).locale(Locale.app)))
                .font(Theme.serifBold(24, relativeTo: .title2))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { shift(1) } label: { ThemeIcon(symbol: Icon.disclosure, size: 18).frame(width: 44, height: 44) }
                .accessibilityLabel("下个月")
                .disabled(isCurrentMonth).opacity(isCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(Theme.ink)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaySymbols(calendar), id: \.self) { day in
                Text(day).font(.caption.weight(.bold)).foregroundStyle(Theme.ink3).frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date { dayCell(date) } else { Color.clear.frame(height: 48) }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let minutes = Self.minutes(model.readingSeconds, on: date)
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let future = date > Date()
        return Button { selected = date } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(minutes >= goalMinutes ? .bold : .regular)).monospacedDigit()
                Rectangle().fill(minutes >= goalMinutes ? Theme.onClay : .clear).frame(width: 12, height: 2)
            }
            .foregroundStyle(minutes > 0 ? Theme.onClay : (future ? Theme.ink3.opacity(0.5) : Theme.ink))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(minutes > 0 ? Theme.clay.opacity(Self.intensity(minutes: minutes, goal: goalMinutes)) : Theme.surface2.opacity(0.5))
            .overlay { if isSelected { Rectangle().strokeBorder(Theme.rulePaint, lineWidth: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(date.formatted(.dateTime.month().day().locale(Locale.app)) + "，\(minutes) 分钟")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayDetail: some View {
        let minutes = Self.minutes(model.readingSeconds, on: selected)
        let sessions = model.visibleSessions.filter { calendar.isDate($0.start, inSameDayAs: selected) }
        let books = Dictionary(grouping: sessions, by: \.title).map { ($0.key, $0.value.reduce(0) { $0 + $1.seconds }) }.sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 10) {
            Text(selected.formatted(.dateTime.month().day().weekday(.wide).locale(Locale.app)))
                .font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(minutes)").font(Theme.serifBold(40, relativeTo: .largeTitle)).monospacedDigit()
                Text("分钟").font(.subheadline).foregroundStyle(Theme.ink2)
                Spacer()
                if minutes >= goalMinutes { Text("达成目标").font(.caption.weight(.bold)).foregroundStyle(Theme.accent) }
            }
            ForEach(books, id: \.0) { title, seconds in
                HStack {
                    Text(title.isEmpty ? "未命名" : "《\(title)》").font(Theme.serif(15)).lineLimit(1)
                    Spacer()
                    Text("\(max(1, Int(seconds / 60))) 分").font(.footnote).monospacedDigit().foregroundStyle(Theme.ink2)
                }
                .overlay(alignment: .bottom) { RowDivider().offset(y: 6) }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private var monthSummary: some View {
        let monthDays = days.compactMap { $0 }
        let read = monthDays.filter { Self.minutes(model.readingSeconds, on: $0) >= 1 }.count
        let reached = monthDays.filter { Self.minutes(model.readingSeconds, on: $0) >= goalMinutes }.count
        let total = monthDays.reduce(0) { $0 + Self.minutes(model.readingSeconds, on: $1) }
        return HStack(spacing: 0) {
            summary("\(read)", "阅读天数")
            summary("\(reached)", "达标天数")
            summary("\(total)", "本月分钟")
        }
        .padding(.top, 4)
    }
    private func summary(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.serifBold(26, relativeTo: .title2)).monospacedDigit().foregroundStyle(Theme.ink)
            Text(L(label)).font(.caption).foregroundStyle(Theme.ink3)
        }
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
