import SwiftUI

/// 「暖页」Tab 1 —— 今天（治愈系陪伴首页）：
/// 时段问候与添书快捷入口、每日阅读目标进度环、接着来双轨大卡（支持「读跟上听」一键对齐）、
/// 三张柔色陪伴场景卡（睡前听、通勤听、专注读）、今日一句柔色摘句卡、最近放进书房横向书架。
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var focusStore: FocusSessionStore = .shared
    @AppStorage("goal.dailyMinutes") private var goalMinutes = 30
    @State private var showingSources = false
    @State private var importHubToken = UUID()
    @State private var showingFocusSheet = false

    private var heroEntry: ShelfEntry? {
        model.lastReadingBook
            ?? model.visibleEntries.first { $0.local && !$0.isComic }
            ?? model.visibleEntries.first { $0.local }
    }

    private var recentShelfBooks: [ShelfEntry] {
        Array(
            model.visibleEntries
                .filter(\.local)
                .sorted { max($0.addedAt ?? 0, model.readingRecency(for: $0)) > max($1.addedAt ?? 0, model.readingRecency(for: $1)) }
                .prefix(8)
        )
    }

    private var todayMinutes: Int {
        let calendar = Calendar.current
        let sessionSeconds = model.visibleSessions.filter { calendar.isDateInToday($0.start) }.reduce(0) { $0 + $1.seconds }
        let fallbackSeconds = model.readingSeconds[AppModel.dayKey(Date())] ?? 0
        return Int(max(sessionSeconds, fallbackSeconds) / 60)
    }

    private var streakDays: Int {
        AppModel.readingStreak(model.readingSeconds).current
    }

    private var greeting: (eyebrow: String, title: String, subtitle: String, symbol: String) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:
            return ("清晨好时光", "早安，留几页给今天", "晨光微暖，读一小段再出发", "sun.horizon.fill")
        case 11..<14:
            return ("午间小憩", "午安，歇一会儿眼睛", "泡杯热茶，听两章或翻几页都好", "cup.and.saucer.fill")
        case 14..<18:
            return ("午后慢读", "下午好，风很轻", "挑一本顺手的书，慢慢往下走", "sun.max.fill")
        case 18..<22:
            return ("傍晚归途", "晚上好，卸下一天疲惫", "戴上耳机听一章，或者静静读一会儿", "sparkles")
        default:
            return ("夜深陪伴", "夜深了，温柔收尾", "开启 20 分钟睡前定时，听着故事入眠", "moon.stars.fill")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                headerSection
                goalBannerCard
                if let entry = heroEntry {
                    continueHeroCard(entry)
                    sceneCardsSection(entry)
                } else {
                    emptyTodayCard
                }
                warmDailyQuoteSection
                if !recentShelfBooks.isEmpty {
                    recentBooksSection
                }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, Theme.space3)
            .padding(.bottom, Theme.space6)
            .frame(maxWidth: Theme.pageWidth)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: showingSources) { _, shown in
            if shown { model.holdFileImportPresentation(importHubToken) }
        }
        .onChange(of: model.fileImportRequested) { _, requested in
            if requested { showingSources = false }
        }
        .sheet(isPresented: $showingSources, onDismiss: {
            model.releaseFileImportPresentation(importHubToken)
        }) {
            ImportHubView().environmentObject(model).tint(Theme.accent)
        }
        .sheet(isPresented: $showingFocusSheet) {
            if let entry = heroEntry {
                let chapter = min(max(0, entry.progress.chapter), max(0, entry.chapterCount - 1))
                FocusStartView(
                    entry: entry,
                    bookID: entry.id,
                    bookTitle: entry.title,
                    chapter: chapter,
                    chapterTitle: "第 \(chapter + 1) 章"
                )
                .environmentObject(model)
                .tint(Theme.clayDeep)
            }
        }
    }

    // MARK: - 1. 温暖时段问候页眉

    private var headerSection: some View {
        HStack(alignment: .top, spacing: Theme.space3) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: greeting.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(greeting.eyebrow)
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    if streakDays > 0 {
                        Text("· 连续 \(streakDays) 天")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.sageInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.sage, in: Capsule())
                    }
                }
                Text(greeting.title)
                    .font(Theme.serif(26, relativeTo: .title))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(greeting.subtitle)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.space2)
            Button {
                Haptics.light()
                showingSources = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: Icon.add).font(.system(size: 13, weight: .semibold))
                    Text("添书").font(Theme.sans(13, weight: .semibold))
                }
                .foregroundStyle(Theme.onClay)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Theme.clay, in: Capsule())
                .frame(minHeight: Theme.iconButtonSize)
                .contentShape(Capsule())
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityLabel("添书")
            .accessibilityIdentifier("today.importBook")
        }
    }

    // MARK: - 2. 今日读听目标柔色环卡

    private var goalBannerCard: some View {
        let safeGoal = max(5, goalMinutes)
        let fraction = min(1.0, Double(todayMinutes) / Double(safeGoal))
        let reached = todayMinutes >= safeGoal
        return HStack(spacing: Theme.space4) {
            ZStack {
                Circle()
                    .stroke(Theme.butterInk.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.04, fraction))
                    .stroke(reached ? Theme.sageInk : Theme.clay, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(todayMinutes)")
                        .font(Theme.rounded(15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(reached ? Theme.sageInk : Theme.butterInk)
                    Text("min")
                        .font(Theme.rounded(9, weight: .medium))
                        .foregroundStyle(reached ? Theme.sageInk : Theme.butterInk)
                }
            }
            .frame(width: 54, height: 54)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reached ? "今日陪伴已达成" : "今日陪伴小目标")
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    SealBadge(
                        text: "\(todayMinutes) / \(safeGoal) 分钟",
                        color: reached ? Theme.sageInk : Theme.butterInk,
                        background: reached ? Theme.sage : Theme.surface.opacity(0.75)
                    )
                }
                Text(reached
                     ? "已经静静陪伴了自己 \(todayMinutes) 分钟，剩下的时间随心翻阅。"
                     : "还差 \(max(1, safeGoal - todayMinutes)) 分钟完成今日小目标，读几页或听一章都算数。")
                    .font(Theme.sans(12.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.cardInset)
        .background(reached ? Theme.sage.opacity(0.65) : Theme.butter, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: Theme.rule)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.goalCard")
    }

    // MARK: - 3. 接着来 · 读听双轨陪伴大卡

    private func continueHeroCard(_ entry: ShelfEntry) -> some View {
        let readCh = min(max(1, entry.progress.chapter + 1), max(1, entry.chapterCount))
        let listenPos = entry.listeningProgress
        let listenCh = listenPos.map { min(max(1, $0.chapter + 1), max(1, entry.chapterCount)) }
        let dualDiverged: Bool = {
            guard !entry.isComic, entry.hasListened == true, let lp = listenPos else { return false }
            return lp.chapter != entry.progress.chapter || abs(lp.position - entry.progress.position) > 2
        }()

        let bodyLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.space4))
        let actionsLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space2))
            : AnyLayout(HStackLayout(spacing: Theme.space3))

        return VStack(alignment: .leading, spacing: Theme.space4) {
            HStack(spacing: Theme.space2) {
                SealBadge(text: "接着来", color: Theme.accent, background: Theme.accentSoft)
                if entry.started, entry.chapterCount > 0 {
                    Text("读至第 \(readCh) / \(entry.chapterCount) \(entry.isComic ? "页" : "章")")
                        .font(Theme.rounded(12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                } else {
                    Text("刚放进书房 · 随时翻开")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: 0)
                if entry.started {
                    Text(entry.readFraction >= 0.995 ? "已读完" : entry.percentText)
                        .font(Theme.rounded(12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(entry.readFraction >= 0.995 ? Theme.sageInk : Theme.accent)
                }
            }

            bodyLayout {
                CoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 84)
                    .softCardShadow()
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title)
                        .font(Theme.serif(20, relativeTo: .title3))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.author.isEmpty ? entry.format : "\(entry.author) · \(entry.format)")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                    ProgressLine(value: entry.started ? entry.readFraction : 0, track: Theme.surface2, tint: Theme.clay, height: 6)
                        .padding(.top, 4)
                    if let listenCh, !entry.isComic, entry.hasListened == true {
                        HStack(spacing: 6) {
                            Image(systemName: Icon.listen)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.skyInk)
                                .accessibilityHidden(true)
                            Text("听书停在第 \(listenCh) 章")
                                .font(Theme.rounded(11.5, weight: .medium))
                                .foregroundStyle(Theme.skyInk)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Theme.sky, in: Capsule())
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if dualDiverged, let lp = listenPos {
                Button {
                    Haptics.light()
                    model.saveProgress(entry.id, chapter: lp.chapter, position: lp.position)
                    model.open(entry, chapter: lp.chapter, position: lp.position)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: Icon.jumpHere)
                            .font(.system(size: 13, weight: .semibold))
                        Text("读跟上听 · 跳到听书第 \(lp.chapter + 1) 章继续看")
                            .font(Theme.sans(13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: Icon.disclosure)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityIdentifier("today.syncReadToListen")
            }

            actionsLayout {
                ClayButton(entry.started ? "继续阅读" : "翻开第一页") {
                    Haptics.light()
                    model.open(entry)
                }
                .accessibilityIdentifier("today.continueReading")

                if !entry.isComic {
                    Button {
                        Haptics.light()
                        model.listen(entry.id)
                    } label: {
                        ListenLabel(bookID: entry.id, player: model.player)
                    }
                    .buttonStyle(SecondaryButtonStyle(emphasized: true))
                    .accessibilityIdentifier("today.continueListening")
                }
            }
        }
        .padding(Theme.space5)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: Theme.rule)
        }
        .softCardShadow()
    }

    // MARK: - 4. 三张治愈系陪伴场景卡

    private func sceneCardsSection(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            SectionHeader(title: "选一种舒服的陪伴")
            let gridLayout = typeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.flexible(), spacing: Theme.space3),
                   GridItem(.flexible(), spacing: Theme.space3),
                   GridItem(.flexible(), spacing: Theme.space3)]
            LazyVGrid(columns: gridLayout, spacing: Theme.space3) {
                sceneCard(
                    title: "睡前听",
                    subtitle: "20m 温柔定时",
                    symbol: "moon.zzz.fill",
                    bg: Theme.lav,
                    ink: Theme.lavInk,
                    identifier: "today.scene.sleep"
                ) {
                    guard !entry.isComic else { model.open(entry); return }
                    Haptics.light()
                    model.player.setSleep(minutes: 20)
                    model.listen(entry.id)
                }
                sceneCard(
                    title: "通勤听",
                    subtitle: "接着上次那句",
                    symbol: "headphones",
                    bg: Theme.sky,
                    ink: Theme.skyInk,
                    identifier: "today.scene.commute"
                ) {
                    guard !entry.isComic else { model.open(entry); return }
                    Haptics.light()
                    model.listen(entry.id)
                }
                sceneCard(
                    title: "专注读",
                    subtitle: focusStore.phase == .running ? "正在计时中" : "25m 静心沉浸",
                    symbol: "leaf.fill",
                    bg: Theme.sage,
                    ink: Theme.sageInk,
                    identifier: "today.scene.focus"
                ) {
                    Haptics.light()
                    showingFocusSheet = true
                }
            }
        }
    }

    private func sceneCard(
        title: String,
        subtitle: String,
        symbol: String,
        bg: Color,
        ink: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.space2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface.opacity(0.72), in: Circle())
                    .accessibilityHidden(true)
                Spacer(minLength: 2)
                Text(title)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.rounded(11.5, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(ink.opacity(0.14), lineWidth: Theme.rule)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityIdentifier(identifier)
    }

    // MARK: - 5. 今日一句柔色卡片

    private var warmDailyQuoteSection: some View {
        PaperCard(padding: Theme.space5) {
            DailyQuoteCard(compact: false)
        }
    }

    // MARK: - 6. 最近放进书房横向书架

    private var recentBooksSection: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            SectionHeader(title: "最近在书房", actionTitle: "逛逛书房") {
                Haptics.selection()
                model.tab = 1
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.space3) {
                    ForEach(recentShelfBooks) { entry in
                        Button {
                            Haptics.light()
                            model.open(entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverView(
                                    title: entry.title,
                                    color: entry.color,
                                    author: entry.author,
                                    image: model.covers[entry.id],
                                    width: 86
                                )
                                .softCardShadow()
                                Text(entry.title)
                                    .font(Theme.serif(13.5))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 86, alignment: .leading)
                                Text(entry.percentText)
                                    .font(Theme.rounded(11, weight: .medium))
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                        .buttonStyle(PressButtonStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 空态

    private var emptyTodayCard: some View {
        EmptyState(
            title: "书房还空着呢",
            detail: "放进一本喜欢的 EPUB、TXT、Markdown 或 PDF，无论看还是听，随时陪你开始。",
            badge: "暖页陪伴",
            actionTitle: "导入第一本书"
        ) {
            showingSources = true
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: Theme.rule)
        }
        .softCardShadow()
    }
}
