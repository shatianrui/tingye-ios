import SwiftUI

/// 余白读页：暖纸续读卡、书名与书封并列、轻量阅读习惯。读听语义仍来自真实使用记录。
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
        VStack(alignment: .leading, spacing: 9) {
            Text("TINGYE / READ & LISTEN")
                .font(Theme.kicker).tracking(1.2).foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 12) {
                Text("给自己，\n一页安静。")
                    .scaledFont(32, weight: .semibold, relativeTo: .largeTitle)
                    .foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                CircleIconButton(systemName: Icon.search, label: "搜索书架") {
                    model.tab = 0
                    model.shelfSearchRequested = true
                }.accessibilityIdentifier("now.search")
            }
        }
    }

    private func continueSection(_ entry: ShelfEntry) -> some View {
        let current = player.book?.id == entry.id
        let actions = model.resumeActions(for: entry)
        let fraction = current && actions.prefersListening ? player.progress : entry.readFraction
        let chapter = current && actions.prefersListening ? player.chapter : entry.progress.chapter
        return VStack(alignment: .leading, spacing: 16) {
            Label(actions.playing ? "正在听" : actions.prefersListening ? "上次听到这里" : actions.started ? "继续上次的阅读" : "从这本开始", systemImage: actions.prefersListening ? Icon.listen : Icon.bookmark(false))
                .font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title).font(Theme.serifSemibold(22, relativeTo: .title2))
                        .foregroundStyle(Theme.heroInk).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                    Text(entry.author).font(.caption).foregroundStyle(Theme.ink2)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    Text("第 \(chapter + 1) / \(max(1, entry.chapterCount)) 章")
                        .font(.caption).foregroundStyle(Theme.ink2).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 82)
                        .accessibilityHidden(true)
                }
            }
            VStack(spacing: 8) {
                HStack {
                    Text("\(current && actions.prefersListening ? "本章" : "已读") \(Int((fraction * 100).rounded()))%")
                    Spacer()
                    Text(current && actions.prefersListening ? "句子进度" : "全书")
                }
                .font(.caption).foregroundStyle(Theme.ink2).monospacedDigit()
                ProgressBar(value: fraction, track: Theme.line, tint: Theme.accent, height: 3).accessibilityHidden(true)
            }
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
        .padding(20)
        .background(Theme.hero, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .contextMenu {
            Button { detail = entry.id } label: { Label("书籍详情", systemImage: Icon.info) }
            if current { Button { player.stop() } label: { Label("结束听书", systemImage: Icon.stopListening) } }
        }
    }

    private func readButton(_ entry: ShelfEntry, title: String, compact: Bool = false) -> some View {
        Button { Haptics.light(); model.open(entry) } label: {
            if compact { alternateIcon(Icon.read) }
            else { HStack(spacing: 8) { Text(title); ThemeIcon(symbol: Icon.disclosure, size: 16) } }
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
                    HStack { Text("与书相伴的一周"); Spacer(); Text("今天 \(todayMinutes) 分钟") }
                    VStack(alignment: .leading, spacing: 6) { Text("与书相伴的一周"); Text("今天 \(todayMinutes) 分钟") }
                }
                .font(.caption).foregroundStyle(Theme.ink3)
                HStack {
                    ForEach(week, id: \.self) { date in
                        let read = (model.readingSeconds[AppModel.dayKey(date)] ?? 0) >= 60
                        let today = Calendar.current.isDateInToday(date)
                        VStack(spacing: 7) {
                            ZStack {
                                Circle().fill(read ? Theme.marker : Theme.surface2)
                                if read { ThemeIcon(symbol: Icon.checkmark, size: 12).foregroundStyle(Theme.onMarker) }
                                else if today { Circle().strokeBorder(Theme.accent, lineWidth: 1) }
                            }.frame(width: 26, height: 26)
                            Text(["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: date) - 1])
                                .font(.caption2).foregroundStyle(Theme.ink3)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("过去七天有 \(week.filter { (model.readingSeconds[AppModel.dayKey($0)] ?? 0) >= 60 }.count) 天阅读，今日 \(todayMinutes) 分钟，目标 \(goalMinutes) 分钟。查看足迹")
    }

    private func bookRows(_ title: String, _ rows: [ShelfEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.headline.weight(.semibold)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { model.tab = 0 } label: {
                    HStack(spacing: 2) { Text("书架"); ThemeIcon(symbol: Icon.disclosure, size: 14) }
                        .font(.caption).foregroundStyle(Theme.ink3).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain)
            }
            ForEach(rows) { entry in
                if entry.id != rows.first?.id { RowDivider(inset: typeSize.isAccessibilitySize ? 0 : 56) }
                Button { Haptics.light(); model.open(entry) } label: {
                    HStack(spacing: 14) {
                        if !typeSize.isAccessibilitySize {
                            BookCoverView(title: entry.title, color: entry.color, image: model.covers[entry.id], width: 46)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.title).font(Theme.serifSemibold(16, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Text(entry.author + (entry.started ? " · 已读 \(entry.percentText)" : ""))
                                .font(.caption).foregroundStyle(Theme.ink3)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        ThemeIcon(symbol: Icon.disclosure, size: 16).foregroundStyle(Theme.ink3)
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
            Text("从一本书开始。").font(Theme.serifSemibold(23, relativeTo: .title2)).foregroundStyle(Theme.ink)
            Text("导入 EPUB、TXT、PDF 或 MOBI，可以读，也可以合上眼睛听。")
                .font(.subheadline).foregroundStyle(Theme.ink2)
            actionLayout {
                Button("导入书籍") { importing = true }.buttonStyle(PrimaryButtonStyle())
                Button("更多方式") { showingSources = true }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
