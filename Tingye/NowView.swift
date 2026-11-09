import SwiftUI

/// 此刻：先回到最近阅读的书；听书保持为阅读之外的辅助入口。
struct NowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject var player: SpeechPlayer
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @State private var importing = false
    @State private var showingSources = false
    @State private var detail: String?

    private var focus: ShelfEntry? {
        model.lastReadingBook
            ?? model.visibleEntries.first { $0.local && !$0.isComic }
            ?? model.visibleEntries.first { $0.local }
    }
    private var recent: [ShelfEntry] {
        Array(model.visibleEntries.filter { $0.local && model.readingRecency(for: $0) > 0 && $0.id != focus?.id }
            .sorted { model.readingRecency(for: $0) > model.readingRecency(for: $1) }.prefix(3))
    }
    private var unopened: [ShelfEntry] {
        Array(model.visibleEntries.filter { $0.local && !$0.started && $0.id != focus?.id }
            .sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.prefix(3))
    }
    private var readingDays: [String: Double] {
        model.visibleSessions.filter { !$0.listening }.reduce(into: [:]) { result, session in
            result[AppModel.dayKey(session.start), default: 0] += session.seconds
        }
    }
    private var streak: Int { AppModel.readingStreak(readingDays).current }
    private var todayMinutes: Int { Int((readingDays[AppModel.dayKey(Date())] ?? 0) / 60) }
    private func progressLabel(_ entry: ShelfEntry) -> String {
        guard entry.started else { return "尚未开始阅读" }
        let unit = entry.isComic || entry.format.uppercased() == "PDF" ? "页" : "章"
        return "读至第 \(entry.progress.chapter + 1) / \(max(1, entry.chapterCount)) \(unit) · \(entry.percentText)"
    }
    private var actionLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                masthead
                if let focus { continueSection(focus) } else { welcome }
                todaySummary
                if !recent.isEmpty { bookRows("最近在读", recent) }
                if !unopened.isEmpty { bookRows("待读清单", unopened) }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 10).padding(.bottom, 24)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $detail) { id in
            BookDetailView(entryID: id)
        }
        .bookImporter(isPresented: $importing)
        .sheet(isPresented: $showingSources) { ImportHubView().environmentObject(model).tint(Theme.accent) }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("听页 · 留一点时间给自己").font(.caption).foregroundStyle(Theme.ink2)
                    Text("此刻").font(Theme.serifBold(34, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                }
                Spacer()
                CircleIconButton(systemName: Icon.search, label: "搜索书库") {
                    model.tab = 0
                    model.shelfSearchRequested = true
                }.accessibilityIdentifier("now.search")
            }
            Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale.app)))
                .font(.caption).foregroundStyle(Theme.ink2)
        }
    }

    private func continueSection(_ entry: ShelfEntry) -> some View {
        let current = player.book?.id == entry.id
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill").accessibilityHidden(true)
                Text("把故事，接着读下去").font(.caption.weight(.medium))
                Spacer(minLength: 0)
            }.foregroundStyle(Theme.accent)
            actionLayout {
                BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 100)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.started ? "继续读这本书" : "翻开一本书")
                        .font(.caption).foregroundStyle(Theme.accent)
                    Button { detail = entry.id } label: {
                        Text(entry.title).font(Theme.serifSemibold(23, relativeTo: .title2))
                            .foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                    }.buttonStyle(.plain)
                    Text(entry.author.isEmpty ? L("佚名") : entry.author)
                        .font(.caption).foregroundStyle(Theme.ink2)
                    Text(progressLabel(entry))
                        .font(.caption).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("now.readingProgress")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if entry.started {
                ProgressBar(value: entry.readFraction, track: Theme.ink.opacity(0.08), tint: Theme.accent, height: 3)
                    .accessibilityHidden(true)
            }
            readButton(entry).buttonStyle(PrimaryButtonStyle(height: 50))
            HStack(spacing: 12) {
                Button { detail = entry.id } label: {
                    Text("目录与书摘").frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("now.readingDetails")
                Spacer(minLength: 8)
                if !entry.isComic { listenButton(entry, current: current) }
            }
            .font(.caption).foregroundStyle(Theme.ink2)
            .buttonStyle(.plain)
            .frame(minHeight: 44)
        }
        .padding(24)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.heroRadius).strokeBorder(Theme.line, lineWidth: 1) }
        .contextMenu {
            Button { model.open(entry) } label: { Label("阅读", systemImage: Icon.read) }
            Button { detail = entry.id } label: { Label("书籍详情", systemImage: Icon.info) }
            if !entry.isComic { Button { model.listen(entry.id) } label: { Label("听书", systemImage: Icon.listen) } }
            if current { Button { player.stop() } label: { Label("结束听书", systemImage: Icon.stopListening) } }
        }
    }

    private func readButton(_ entry: ShelfEntry) -> some View {
        Button { Haptics.light(); model.open(entry) } label: {
            Text(model.resumeActions(for: entry).readingTitle)
        }
        .accessibilityIdentifier("continue.reading")
        .accessibilityLabel("\(model.resumeActions(for: entry).readingTitle)《\(entry.title)》")
    }

    private func listenButton(_ entry: ShelfEntry, current: Bool) -> some View {
        Button {
            Haptics.light()
            if current {
                if !player.playing { player.resume() }
                model.showListeningReader()
            } else { model.listen(entry.id) }
        } label: {
            Label(current && player.playing ? "回到朗读正文" : "听这本书", systemImage: Icon.listen)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("now.listen")
        .accessibilityLabel("\(current && player.playing ? "回到朗读正文" : "听这本书")《\(entry.title)》")
        .accessibilityHint("辅助朗读，保留当前阅读位置")
    }

    private var todaySummary: some View {
        Button { Haptics.selection(); model.tab = 2 } label: {
            actionLayout {
                ZStack {
                    Circle().stroke(Theme.line, lineWidth: 5)
                    Circle().trim(from: 0, to: min(1, CGFloat(todayMinutes) / CGFloat(max(1, goalMinutes))))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "leaf").font(.title3).foregroundStyle(Theme.accent)
                }
                .frame(width: 48, height: 48).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(todayMinutes) 分钟").font(Theme.sans(20, weight: .bold)).monospacedDigit()
                    Text("今日阅读 · 目标 \(goalMinutes) 分钟").font(.caption2).foregroundStyle(Theme.ink2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text("连续 \(streak) 天").font(Theme.sans(20, weight: .bold)).monospacedDigit()
                    Text("慢慢读，也是一种抵达。").font(.caption2).foregroundStyle(Theme.ink2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.ink).padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看阅读足迹与目标")
    }

    private func bookRows(_ title: String, _ rows: [ShelfEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L(title)).font(Theme.serifBold(22, relativeTo: .title2)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { model.tab = 0 } label: {
                    Text("全部书籍").font(.caption).foregroundStyle(Theme.accent)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("书库")
            }
            ForEach(rows) { entry in
                Button { Haptics.light(); model.open(entry) } label: {
                    HStack(spacing: 14) {
                        BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 56)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Text((entry.author.isEmpty ? L("佚名") : entry.author) + " · " + entry.format).font(.caption).foregroundStyle(Theme.ink2)
                            Text(entry.started ? progressLabel(entry) : "待读")
                                .font(.caption).foregroundStyle(Theme.accent)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 96).contentShape(Rectangle())
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
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: Icon.read).font(.system(size: 32)).foregroundStyle(Theme.accent)
            Text("从第一本书开始").font(Theme.sans(23, weight: .bold)).foregroundStyle(Theme.ink)
            Text("导入喜欢的书，从这一页开始，留一点时间给阅读。")
                .font(.subheadline).foregroundStyle(Theme.ink2)
            Button("导入书籍") { importing = true }.buttonStyle(PrimaryButtonStyle(height: 50))
            Button("更多传书方式") { showingSources = true }.buttonStyle(SecondaryButtonStyle(height: 50))
        }
        .padding(20).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
