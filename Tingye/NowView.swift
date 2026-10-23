import SwiftUI

/// 刊读页：刊红刊名、红框封面卡、编号目录与七日栏。读听语义仍来自真实使用记录。
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
            VStack(alignment: .leading, spacing: 22) {
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

    /// 刊名：左侧刊红宋体「听页」，右侧搜索；下压 3pt 墨线与日期栏，像《时代》封面顶端的刊头。
    private var masthead: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text("听页")
                    .font(Theme.serifBold(46, relativeTo: .largeTitle)).serifHeavy(46)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(L(headline))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                CircleIconButton(systemName: Icon.search, label: "搜索书架") {
                    model.tab = 0
                    model.shelfSearchRequested = true
                }.accessibilityIdentifier("now.search")
                .padding(.trailing, -10)
            }
            .padding(.bottom, 6)
            Rectangle().fill(Theme.rulePaint).frame(height: Theme.ruleHeavy).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack { dateLine; Spacer(minLength: 8); todayLine }
                VStack(alignment: .leading, spacing: 4) { dateLine; todayLine }
            }
            .font(.caption2)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Theme.line).frame(height: 1).accessibilityHidden(true)
        }
    }
    private var dateLine: some View {
        Text(Date().formatted(.dateTime.year().month().day().weekday(.wide).locale(Locale.app)))
            .fontWeight(.bold).tracking(0.6).foregroundStyle(Theme.ink)
    }
    private var todayLine: some View {
        Text(String(format: L("今日已读 %lld 分钟"), todayMinutes) + (streak > 0 ? " · " + String(format: L("连续 %lld 天"), streak) : ""))
            .foregroundStyle(Theme.ink2)
    }
    private var headline: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 5 ? "夜深，读一页" : hour < 11 ? "清晨读什么" : hour < 17 ? "午后读什么" : "今夜读什么"
    }

    /// 封面卡：刊红粗框 + 墨底白字，书名作封面大标题；正在听时右上角斜贴「正在听」角带。按钮放在封面下方。
    private func continueSection(_ entry: ShelfEntry) -> some View {
        let current = player.book?.id == entry.id
        let actions = model.resumeActions(for: entry)
        let fraction = current && actions.prefersListening ? player.progress : entry.readFraction
        let chapter = current && actions.prefersListening ? player.chapter : entry.progress.chapter
        let frame: CGFloat = 9
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L(actions.prefersListening ? "继续听" : "继续阅读") + " · " + "第 \(chapter + 1) / \(max(1, entry.chapterCount)) 章")
                    .font(Theme.kicker).tracking(1.5).foregroundStyle(Self.coverInk.opacity(0.8))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.trailing, current && player.playing ? 56 : 0)
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.title).font(Theme.serifBold(36, relativeTo: .largeTitle)).serifHeavy(36)
                            .foregroundStyle(Self.coverInk).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(entry.author.isEmpty ? L("佚名") : entry.author)
                            .font(Theme.serif(16, relativeTo: .body)).foregroundStyle(Self.coverInk.opacity(0.75))
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !typeSize.isAccessibilitySize {
                        BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 84)
                            .accessibilityHidden(true)
                    }
                }
                HStack(alignment: .lastTextBaseline) {
                    Text(L(current && actions.prefersListening ? "本章" : "全书"))
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 8)
                    Text("\(Int((fraction * 100).rounded()))")
                        .font(.system(size: 28, weight: .black)).monospacedDigit()
                    + Text("%").font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Self.coverInk)
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
                ProgressBar(value: fraction, track: Color.white.opacity(0.18), tint: Theme.clay, height: 4).accessibilityHidden(true)
            }
            .padding(frame + 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.coverField)
            .overlay(alignment: .topTrailing) { if current && player.playing { nowListeningSash } }
            .overlay { Rectangle().strokeBorder(Theme.clay, lineWidth: frame) }
            .clipped()
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
        .contentShape(Rectangle())
        .contextMenu {
            Button { detail = entry.id } label: { Label("书籍详情", systemImage: Icon.info) }
            if current { Button { player.stop() } label: { Label("结束听书", systemImage: Icon.stopListening) } }
        }
    }

    /// 封面卡底色与字色日夜不变：墨底白字，靠刊红框与页面分开。
    private static let coverField = Color(hex: 0x141414)
    private static let coverInk = Color.white

    /// 杂志特刊式斜角带。
    private var nowListeningSash: some View {
        Text("正在听")
            .font(.system(size: 10, weight: .black)).tracking(2)
            .foregroundStyle(Theme.ink)
            .frame(width: 150).padding(.vertical, 4)
            .background(Theme.bg)
            .rotationEffect(.degrees(45))
            .offset(x: 46, y: 26)
            .accessibilityHidden(true)
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
            .background(Theme.accentSoft, in: Rectangle()).contentShape(Rectangle())
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
                                Rectangle().fill(seconds < 60 ? Theme.line : today ? Theme.clay : Theme.ink)
                                    .frame(height: max(3, 44 * min(1, seconds / 60 / Double(max(1, goalMinutes)))))
                            }
                            .frame(width: 16, height: 44)
                            Text(["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: date) - 1])
                                .font(.caption2.weight(today ? .bold : .regular)).foregroundStyle(today ? Theme.accent : Theme.ink3)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.rulePaint).frame(height: Theme.ruleHeavy) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("过去七天有 \(week.filter { (model.readingSeconds[AppModel.dayKey($0)] ?? 0) >= 60 }.count) 天阅读，今日 \(todayMinutes) 分钟，目标 \(goalMinutes) 分钟。查看足迹")
    }

    private var weekTitle: some View {
        Text("七日").font(Theme.masthead).tracking(1.5).foregroundStyle(Theme.accent)
    }

    /// 栏目：3pt 墨线开栏 + 刊红眉题，行与行之间 1px 细线；行首刊红编号，书名宋体粗，红框封面缩略在右。
    private func bookRows(_ title: String, _ rows: [ShelfEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L(title)).font(Theme.masthead).tracking(1.5).foregroundStyle(Theme.accent).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { model.tab = 0 } label: {
                    Text("全部书架 ›").font(.caption.weight(.semibold)).foregroundStyle(Theme.link).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("书架")
            }
            .padding(.top, 4)
            .overlay(alignment: .top) { Rectangle().fill(Theme.rulePaint).frame(height: Theme.ruleHeavy) }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                RowDivider()
                Button { Haptics.light(); model.open(entry) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 22, weight: .black)).monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .frame(minWidth: 30, alignment: .leading)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.title).font(Theme.serifBold(19, relativeTo: .headline)).foregroundStyle(Theme.ink).serifEmbolden(19)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Text((entry.author.isEmpty ? L("佚名") : entry.author) + " · " + (entry.started ? L("读到") + " " + entry.percentText : L("未读")))
                                .font(.caption).monospacedDigit().foregroundStyle(Theme.ink2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if !typeSize.isAccessibilitySize {
                            BookCoverView(title: entry.title, color: entry.color, image: model.covers[entry.id], width: 44)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 14).frame(minHeight: 72).contentShape(Rectangle())
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
            Text("创刊号：从一本书开始。").font(Theme.serifBold(28, relativeTo: .title2)).foregroundStyle(Theme.ink).serifEmbolden(28)
            Text("导入 EPUB、TXT、PDF 或 MOBI，可以读，也可以合上眼睛听。")
                .font(.subheadline).foregroundStyle(Theme.ink2)
            actionLayout {
                Button("导入书籍") { importing = true }.buttonStyle(PrimaryButtonStyle())
                Button("更多方式") { showingSources = true }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
