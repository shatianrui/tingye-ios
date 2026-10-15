import SwiftUI

/// 今日：刊版首页。刊头（期号与日期）→ 01 封面故事（正在听 / 上次读到）→ 02 今日 → 03 最近在读 → 04 今日一句 → 05 还没开卷。
/// 设计稿：Figma「02 页面 · 日间 / 01 今日 Today」。
struct NowView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var player: SpeechPlayer
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @State private var importing = false
    @State private var showingSources = false
    @State private var detail: String?

    /// 封面故事：正在听的书优先，其次是最近读过的书，再其次是第一本本机书。
    private var focus: ShelfEntry? {
        if let id = player.book?.id, let entry = model.visibleEntries.first(where: { $0.id == id }) { return entry }
        return model.visibleEntries.filter { $0.started && !$0.isComic }.max { $0.progress.updatedAt < $1.progress.updatedAt }
            ?? model.visibleEntries.first { $0.local && !$0.isComic }
    }
    private var recent: [ShelfEntry] {
        Array(model.visibleEntries
            .filter { $0.started && $0.id != focus?.id }
            .sorted { $0.progress.updatedAt > $1.progress.updatedAt }
            .prefix(12))
    }
    private var unopened: [ShelfEntry] {
        Array(model.visibleEntries
            .filter { !$0.started && $0.id != focus?.id }
            .sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }
            .prefix(12))
    }
    private var todayMinutes: Int { Int((model.readingSeconds[AppModel.dayKey(Date())] ?? 0) / 60) }
    /// 连续阅读天数：今天还没读时从昨天往前数，不打断连续记录。
    private var streak: Int {
        let calendar = Calendar.current
        var day = Date()
        if (model.readingSeconds[AppModel.dayKey(day)] ?? 0) < 60 {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while (model.readingSeconds[AppModel.dayKey(day)] ?? 0) >= 60, count < 3650 {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<5: "夜深了"
        case 5..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        default: "晚上好"
        }
    }
    /// 期号：一年中的第几天，像日报的期数。
    private var issue: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return "NO. \(day)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                masthead
                if let focus { coverStory(focus) } else { welcome }
                if focus != nil { todayStrip }
                if !recent.isEmpty { coverRow("03", "最近在读", recent) }
                DailyQuoteCard(number: "04")
                if !unopened.isEmpty { coverRow("05", "还没开卷", unopened) }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $detail) { id in
            BookDetailView(entryID: id).toolbar(.visible, for: .navigationBar)
        }
        .bookImporter(isPresented: $importing)
        .sheet(isPresented: $showingSources) { ImportHubView().environmentObject(model).tint(Theme.accent) }
    }

    // MARK: 刊头

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("听页").font(Theme.headline(20)).foregroundStyle(Theme.ink)
                Spacer()
                (Text(issue + " · ") + Text(Date(), format: .dateTime.year().month(.twoDigits).day(.twoDigits)) + Text(" · ") + Text(Date(), format: .dateTime.weekday(.wide)))
                    .font(Theme.kicker).tracking(1.2)
                    .foregroundStyle(Theme.ink3)
                    .monospacedDigit()
            }
            InkRule(height: Theme.ruleHeavy)
            Text("\(greeting)，\n今天读什么？")
                .font(Theme.headline(38))
                .lineSpacing(2)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
    }

    // MARK: 01 封面故事

    private func coverStory(_ entry: ShelfEntry) -> some View {
        let current = player.book?.id == entry.id
        let listening = current && player.playing
        let fraction = current ? player.progress : entry.readFraction
        return VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "封面故事", number: "01")
            HStack(alignment: .bottom, spacing: 18) {
                Button { Haptics.light(); model.open(entry) } label: {
                    BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 140)
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityLabel("打开《\(entry.title)》")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if listening {
                            Image(systemName: Icon.listening).symbolEffect(.variableColor.iterative, isActive: true)
                        }
                        Text(listening ? "正在听" : current ? "听到一半" : entry.started ? "上次读到" : "从这本开始")
                    }
                    .font(Theme.kicker).tracking(1)
                    .foregroundStyle(Theme.accent)
                    Text(entry.title)
                        .font(Theme.serifBold(30, relativeTo: .title))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text([entry.author, current ? player.chapterTitle : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int((fraction * 100).rounded()))")
                            .font(Theme.display(88))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text("%").font(Theme.display(30)).foregroundStyle(Theme.ink)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(current ? "本章已听 \(Int(fraction * 100))%" : "已读 \(entry.percentText)")
                    Text(current ? "第 \(player.chapter + 1) / \(max(1, player.chapterCount)) 章 · 本章" : "第 \(entry.progress.chapter + 1) / \(max(1, entry.chapterCount)) 章")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ProgressBar(value: fraction, height: 4)
            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    if current { player.toggle() } else { model.listen(entry.id) }
                } label: {
                    Label(listening ? "暂停" : "继续听", systemImage: Icon.playback(listening))
                }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
                .accessibilityLabel(listening ? "暂停朗读" : "听《\(entry.title)》")
                .accessibilityIdentifier("now.listen")
                Button { Haptics.light(); model.open(entry) } label: {
                    Text(entry.started ? "继续阅读" : "开始阅读")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("continue.reading")
                .accessibilityLabel("\(entry.started ? "继续阅读" : "开始阅读")《\(entry.title)》，已读 \(entry.percentText)")
            }
        }
        .contextMenu {
            Button { detail = entry.id } label: { Label("书籍详情", systemImage: Icon.info) }
            if current { Button { player.stop() } label: { Label("结束听书", systemImage: Icon.stopListening) } }
        }
    }

    // MARK: 02 今日

    private var todayStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("02", "今日", link: "足迹") { model.tab = 2 }
            Button { Haptics.selection(); model.tab = 2 } label: {
                HStack(alignment: .top, spacing: 0) {
                    stat("\(todayMinutes)", unit: "分钟", label: "今日")
                    stat("\(min(999, Int(Double(todayMinutes) / Double(max(1, goalMinutes)) * 100)))", unit: "%", label: "目标 \(goalMinutes) 分钟", divider: true)
                    stat("\(streak)", unit: "天", label: "连续", divider: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(PressButtonStyle(scale: 0.98))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日 \(todayMinutes) 分钟，目标 \(goalMinutes) 分钟，连续 \(streak) 天。轻点查看足迹")
        }
    }

    private func stat(_ value: String, unit: String, label: String, divider: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.display(52))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink2)
            }
            Text(label).font(Theme.kicker).tracking(0.8).foregroundStyle(Theme.ink3).lineLimit(1)
        }
        .padding(.leading, divider ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { if divider { Rectangle().fill(Theme.line).frame(width: 1) } }
    }

    // MARK: 横排封面

    private func sectionHeader(_ number: String, _ title: String, link: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            InkRule()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number).font(Theme.kicker).tracking(1.2).foregroundStyle(Theme.accent)
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                if let link {
                    Button(action: action) {
                        Text(link + " →").font(.footnote.weight(.medium)).foregroundStyle(Theme.ink2).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func coverRow(_ number: String, _ title: String, _ rows: [ShelfEntry]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(number, title, link: "书架") { model.tab = 1 }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(rows) { entry in coverTile(entry) }
                }
                .padding(.horizontal, Theme.inset)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Theme.inset)
        }
    }

    private func coverTile(_ entry: ShelfEntry) -> some View {
        Button { Haptics.light(); model.open(entry) } label: {
            VStack(alignment: .leading, spacing: 8) {
                BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 108)
                    .overlay(alignment: .bottomTrailing) {
                        if player.book?.id == entry.id && player.playing {
                            Image(systemName: Icon.listening)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.onMarker)
                                .frame(width: 24, height: 24)
                                .background(Theme.marker)
                                .padding(6)
                        }
                    }
                Text(entry.title)
                    .font(Theme.serifSemibold(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if entry.started {
                    ProgressBar(value: entry.readFraction, height: 3)
                } else {
                    Text(entry.author.isEmpty ? model.category(entry) : entry.author)
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
            .frame(width: 108, alignment: .leading)
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityLabel("\(entry.started ? "继续阅读" : "开始阅读")《\(entry.title)》，\(entry.percentText)")
        .contextMenu {
            Button { model.open(entry) } label: { Label(entry.started ? "继续阅读" : "开始阅读", systemImage: Icon.read) }
            if !entry.isComic {
                Button { model.listen(entry.id) } label: { Label("听书", systemImage: Icon.listen) }
            }
            Button { detail = entry.id } label: { Label("书籍详情", systemImage: Icon.info) }
        }
    }

    // MARK: 空书架

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "创刊号", number: "01")
            Text("从一本书开始。")
                .font(Theme.serifBold(30, relativeTo: .title))
                .foregroundStyle(Theme.ink)
            Text("导入 EPUB、TXT、PDF 或 MOBI，可以读，也可以合上眼睛听。")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("导入书籍") { importing = true }.buttonStyle(PrimaryButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
                Button("更多方式") { showingSources = true }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
    }
}
