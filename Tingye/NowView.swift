import SwiftUI

/// 刊读页：报头、继续阅读卡、编号目录与七日栏。读听语义仍来自真实使用记录。
struct NowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject var player: SpeechPlayer
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @State private var importing = false
    @State private var showingSources = false
    @State private var detail: String?

    private var focus: ShelfEntry? {
        if player.playing, let id = player.book?.id, let entry = model.visibleEntries.first(where: { $0.id == id }) { return entry }
        return model.visibleEntries.filter { $0.started && !$0.isComic }.max { $0.progress.updatedAt < $1.progress.updatedAt }
            ?? model.visibleEntries.first { $0.local && !$0.isComic }
    }
    private var recent: [ShelfEntry] {
        Array(model.visibleEntries.filter { $0.started && $0.id != focus?.id }
            .sorted { $0.progress.updatedAt > $1.progress.updatedAt }.prefix(3))
    }
    private var unopened: [ShelfEntry] {
        Array(model.visibleEntries.filter { !$0.started && $0.id != focus?.id }
            .sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.prefix(3))
    }
    private var streak: Int { AppModel.readingStreak(model.readingSeconds).current }
    private var todayMinutes: Int { Int((model.readingSeconds[AppModel.dayKey(Date())] ?? 0) / 60) }
    private var week: [Date] {
        (-6...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) }
    }
    private var actionLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                masthead.zIndex(2)
                if let focus { continueSection(focus) } else { welcome }
                if !recent.isEmpty { bookRows("最近在读", recent) }
                if focus != nil { readingWeek }
                if !unopened.isEmpty { bookRows("待读清单", unopened) }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $detail) { id in
            BookDetailView(entryID: id).toolbar(.visible, for: .navigationBar)
        }
        .bookImporter(isPresented: $importing)
        .sheet(isPresented: $showingSources) { ImportHubView().environmentObject(model).tint(Theme.accent) }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TINGYE / READ")
                .font(Theme.masthead).tracking(1.5)
                .foregroundStyle(Theme.ink2)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 12) {
                Text(L(headline))
                    .scaledFont(38, weight: .bold, relativeTo: .largeTitle)
                    .tracking(-0.8)
                    .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                CircleIconButton(systemName: Icon.search, label: "搜索书架") {
                    model.tab = 0
                    model.shelfSearchRequested = true
                }.accessibilityIdentifier("now.search")
            }
            Text(Date().formatted(.dateTime.year().month().day().weekday(.wide).locale(Locale.app)) + " · " + String(format: L("今日已读 %lld 分钟"), todayMinutes) + (streak > 0 ? " · " + String(format: L("连续 %lld 天"), streak) : ""))
                .font(.caption).foregroundStyle(Theme.ink2)
        }
    }
    private var headline: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 5 ? "夜深，读一页" : hour < 11 ? "清晨读什么" : hour < 17 ? "午后读什么" : "今夜读什么"
    }

    private func continueSection(_ entry: ShelfEntry) -> some View {
        let current = player.book?.id == entry.id
        let actions = model.resumeActions(for: entry)
        let fraction = current && actions.prefersListening ? player.progress : entry.readFraction
        let chapter = current && actions.prefersListening ? player.chapter : entry.progress.chapter
        return VStack(alignment: .leading, spacing: 16) {
            Text("CONTINUE / 正在读")
                .font(Theme.masthead).tracking(1.5).foregroundStyle(Theme.ink2)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 18) {
                if !typeSize.isAccessibilitySize {
                    BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 112)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title).font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.ink).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !entry.author.isEmpty {
                        Text(entry.author).font(.caption).foregroundStyle(Theme.ink2)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    }
                    Text("\(Int((fraction * 100).rounded()))% · 第 \(chapter + 1)/\(max(1, entry.chapterCount)) 章")
                        .font(Theme.masthead).tracking(1.5).foregroundStyle(Theme.accent)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int((fraction * 100).rounded()))").font(Theme.display(40)).foregroundStyle(Theme.ink)
                        Text("/ 100 · " + (current && actions.prefersListening ? "本章" : "全书")).font(Theme.masthead).tracking(1.5).foregroundStyle(Theme.ink2)
                    }
                    .monospacedDigit()
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ProgressBar(value: fraction, track: Theme.line, tint: Theme.accent, height: 2).accessibilityHidden(true)
            actionLayout {
                if actions.prefersListening {
                    listenButton(entry, title: actions.listeningTitle).buttonStyle(PrimaryButtonStyle())
                    readButton(entry, title: actions.readingTitle).buttonStyle(SecondaryButtonStyle())
                } else {
                    readButton(entry, title: actions.readingTitle).buttonStyle(PrimaryButtonStyle())
                    listenButton(entry, title: actions.listeningTitle).buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(16)
        .glassCard()
        .contextMenu {
            Button { detail = entry.id } label: { Label("书籍详情", systemImage: Icon.info) }
            if current { Button { player.stop() } label: { Label("结束听书", systemImage: Icon.stopListening) } }
        }
    }

    private func readButton(_ entry: ShelfEntry, title: String, compact: Bool = false) -> some View {
        Button { Haptics.light(); model.open(entry) } label: {
            if compact { alternateIcon(Icon.read) }
            else { HStack(spacing: 8) { Text(L(title)); ThemeIcon(symbol: Icon.disclosure, size: 16) } }
        }
        .accessibilityIdentifier("continue.reading")
        .accessibilityLabel("\(title)《\(entry.title)》")
    }
    private func listenButton(_ entry: ShelfEntry, title: String, compact: Bool = false) -> some View {
        Button {
            Haptics.light()
            if player.book?.id == entry.id && player.playing { player.pause() }
            else { model.listen(entry.id) }
        } label: {
            if compact { alternateIcon(player.playing && player.book?.id == entry.id ? Icon.playback(true) : Icon.listen) }
            else { Label(title, systemImage: Icon.playback(player.book?.id == entry.id && player.playing)) }
        }
        .accessibilityIdentifier("now.listen")
        .accessibilityLabel("\(title)《\(entry.title)》")
    }
    private func alternateIcon(_ symbol: String) -> some View {
        ThemeIcon(symbol: symbol, size: 24)
            .foregroundStyle(Theme.accent).frame(width: 48, height: 48)
            .background(Theme.accentSoft, in: Circle()).contentShape(Circle())
    }

    private var readingWeek: some View {
        Button { Haptics.selection(); model.tab = 2 } label: {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack { weekTitle; Spacer(); Text("今天 \(todayMinutes) / \(goalMinutes) 分钟") }
                    VStack(alignment: .leading, spacing: 6) { weekTitle; Text("今天 \(todayMinutes) / \(goalMinutes) 分钟") }
                }
                .font(.caption).foregroundStyle(Theme.ink3)
                HStack {
                    ForEach(week, id: \.self) { date in
                        let seconds = model.readingSeconds[AppModel.dayKey(date)] ?? 0
                        let today = Calendar.current.isDateInToday(date)
                        VStack(spacing: 7) {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle().fill(seconds >= 60 ? Theme.accent : Theme.line)
                                    .frame(height: max(3, 44 * min(1, seconds / 60 / Double(max(1, goalMinutes)))))
                            }
                            .frame(width: 22, height: 44)
                            .overlay(alignment: .bottom) { if today { Circle().fill(Theme.accent).frame(width: 4, height: 4).offset(y: 6) } }
                            Text(["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: date) - 1])
                                .font(.caption2).foregroundStyle(Theme.ink3)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("过去七天有 \(week.filter { (model.readingSeconds[AppModel.dayKey($0)] ?? 0) >= 60 }.count) 天阅读，今日 \(todayMinutes) 分钟，目标 \(goalMinutes) 分钟。查看足迹")
    }

    private var weekTitle: some View {
        Text("七日 / WEEK").font(Theme.masthead).tracking(1.5).foregroundStyle(Theme.ink2)
    }

    private func bookRows(_ title: String, _ rows: [ShelfEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(L(title)).font(Theme.masthead).tracking(1.5).foregroundStyle(Theme.ink2).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { model.tab = 0 } label: {
                    Text("全部 →").font(.caption.weight(.medium)).foregroundStyle(Theme.accent).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("书架")
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { RowDivider() }
                Button { Haptics.light(); model.open(entry) } label: {
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(Theme.masthead)
                            .foregroundStyle(Theme.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Text(entry.author.isEmpty ? "佚名" : entry.author)
                                .font(.caption).foregroundStyle(Theme.ink3)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.started ? entry.percentText : "未读").font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 10).frame(minHeight: 72).contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle(scale: 0.99))
                .accessibilityLabel("\(entry.started ? "继续阅读" : "开始阅读")《\(entry.title)》，\(entry.percentText)")
                .contextMenu {
                    Button { model.open(entry) } label: { Label("阅读", systemImage: Icon.read) }
                    if !entry.isComic { Button { model.listen(entry.id) } label: { Label("听书", systemImage: Icon.listen) } }
                    Button { detail = entry.id } label: { Label("书籍详情", systemImage: Icon.info) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("创刊号：从一本书开始。").scaledFont(26, weight: .bold, relativeTo: .title2).foregroundStyle(Theme.ink)
            Text("导入 EPUB、TXT、PDF 或 MOBI，可以读，也可以合上眼睛听。")
                .font(.subheadline).foregroundStyle(Theme.ink2)
            actionLayout {
                Button("导入书籍") { importing = true }.buttonStyle(PrimaryButtonStyle())
                Button("更多方式") { showingSources = true }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
