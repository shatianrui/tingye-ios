import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 书库：清晰的书目、柔和的封面网格与可跨分组的搜索和整理。
struct ShelfView: View {
    /// 当前所在分组；nil 为书库根目录
    var group: String? = nil
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var filter = "全部"
    @State private var category: String?
    @State private var showingSources = false
    @State private var importHubToken = UUID()
    @State private var importResultsToken = UUID()
    @State private var showingImportResults = false
    @State private var searching = false
    @State private var showingGroups = false
    @AppStorage("shelf.recentSearches") private var savedSearches = ""
    @FocusState private var searchFocused: Bool
    @State private var editing = false
    @State private var selection: Set<String> = []
    @State private var moving = false
    @State private var moveSelection: Set<String> = []
    @State private var removalSelection: Set<String> = []
    @State private var dissolvingGroup: String?
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var removing = false
    @AppStorage("shelf.layout") private var layout = "list"
    @AppStorage("shelf.kind") private var kind = "books"
    #if DEBUG
    @State private var reviewDetail: String?
    #endif

    private var isRoot: Bool { group == nil }
    private var useList: Bool { layout == "list" || typeSize.isAccessibilitySize }
    private var adaptiveRow: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space3)) : AnyLayout(HStackLayout(spacing: Theme.space3)) }
    private var searchText: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var visibleKindEntries: [ShelfEntry] {
        model.visibleEntries.filter { kind == "comics" ? $0.isComic : !$0.isComic }
    }
    private var hasFilters: Bool { filter != "全部" || category != nil }
    private var removableSelection: Set<String> {
        Set(model.entries.filter { selection.contains($0.id) && !$0.sample }.map(\.id))
    }
    private var allSelectedHidden: Bool {
        !selection.isEmpty && selection.allSatisfy { id in model.entries.first { $0.id == id }?.isHidden == true }
    }
    /// 搜索和首页多选跨全部分组；日常浏览只列本层。
    private var pool: [ShelfEntry] {
        if !searchText.isEmpty || (editing && isRoot) { return visibleKindEntries }
        return isRoot ? visibleKindEntries : visibleKindEntries.filter { $0.group == group }
    }
    private var categories: [String] { Set(visibleKindEntries.map { model.category($0) }).sorted() }
    private var filtered: [ShelfEntry] { (showingGroups && isRoot && !searching && !editing ? [] : pool).filter { entry in
        (searchText.isEmpty || (entry.title + entry.author + model.category(entry) + (entry.group ?? "")).localizedCaseInsensitiveContains(searchText)) &&
        (filter == "全部" || (filter == "在读" ? entry.started && entry.readFraction < 0.995 : filter == "读完" ? entry.started && entry.readFraction >= 0.995 : !entry.started)) &&
        (category == nil || model.category(entry) == category)
    } }
    private var sorted: [ShelfEntry] {
        switch model.sortOrder {
        case "title": filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case "author": filtered.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
        case "added": filtered.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }
        case "manual": ManualShelfOrder.sorted(filtered, kind: kind)
        default: filtered.sorted { model.readingRecency(for: $0) > model.readingRecency(for: $1) }
        }
    }
    private var folders: [String] {
        guard !editing, searchText.isEmpty, !hasFilters, !isRoot || showingGroups else { return [] }
        return model.subgroups(of: group).filter { path in model.books(inGroup: path).contains { kind == "comics" ? $0.isComic : !$0.isComic } }
    }
    private var sortLabel: String {
        ["title": "书名", "author": "作者", "added": "添加时间", "manual": "手动"][model.sortOrder] ?? "最近阅读"
    }
    private var totalTime: String {
        let minutes = Int(model.readingSeconds.values.reduce(0, +) / 60)
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }
    private var title: String { group.map { String($0.split(separator: "/").last ?? "") } ?? "书库" }

    var body: some View {
        observedShelf
        #if DEBUG
        .navigationDestination(item: $reviewDetail) { id in BookDetailView(entryID: id) }
        .task {
            if ["shelf", "shelf-list", "shelf-edit"].contains(UIReview.screen) { kind = "books" }
            if ["shelf-grid", "shelf-edit"].contains(UIReview.screen) { layout = "grid" }
            if UIReview.screen == "shelf-list" { layout = "list" }
            if UIReview.screen == "shelf-edit" { editing = true }
            if UIReview.screen == "shelf-comics" { kind = "comics" }
            if (UIReview.screen ?? "").hasPrefix("sources") { showingSources = true }
            if ["detail", "chapters"].contains(UIReview.screen), reviewDetail == nil, isRoot {
                reviewDetail = (model.lastBook ?? model.entries.first(where: \.local))?.id
            }
        }
        #endif
    }

    private var shelfContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 搜索时让出页首与类型栏，键盘上方直接呈现结果；取消后恢复完整浏览入口。
                if isRoot && !searching && !editing { shelfHeader }
                if !isRoot && !searching && !editing {
                    Masthead(title: title, subtitle: shelfSubtitle, titleSize: 28)
                        .padding(.bottom, Theme.space5)
                }
                // 「书房」首页（仅根目录、非搜索、非整理）：正在读大卡 + 今日一句，位于搜索入口之上。
                if isRoot && !searching && !editing, let heroEntry {
                    heroCard(heroEntry).padding(.top, Theme.sectionSpacing)
                    if let latestHighlight { todayQuote(latestHighlight).padding(.top, Theme.sectionSpacing) }
                }
                if !editing {
                    if searching { shelfSearchBar }
                    else { searchEntry.padding(.top, isRoot ? Theme.space5 : 0) }
                }
                if isRoot && !editing && !searching { kindSelector.padding(.top, Theme.space4) }
                shelfControls.padding(.top, editing ? Theme.space4 : Theme.space2)
                if editing || !searchText.isEmpty || hasFilters { scopeNotice.padding(.top, Theme.space2) }
                if sorted.isEmpty && folders.isEmpty {
                    emptyState
                } else {
                    if useList || editing || searching { bookList.padding(.top, Theme.space3) } else { bookGrid.padding(.top, Theme.space2) }
                }
                if searching { recentSearches.padding(.top, Theme.cardInset) }
                if !editing && !searching {
                    Button { showingSources = true } label: { Label { Text("添书") } icon: { ThemeIcon(symbol: Icon.add) } }
                        .buttonStyle(SecondaryButtonStyle()).padding(.top, Theme.cardInset)
                        .accessibilityIdentifier("import.book")
                }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, isRoot ? Theme.space3 : Theme.space1)
            .padding(.bottom, Theme.space6)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
    }

    private var shelfNavigation: some View {
        shelfContent
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .navigationTitle(editing ? "整理书库" : (isRoot ? "" : title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbar(isRoot && !editing ? .hidden : .visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { if editing { editBar } }
        .toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: editing || searching)
        .animation(Theme.smoothSpring, value: editing)
        .onChange(of: showingSources) { _, shown in
            if shown { model.holdFileImportPresentation(importHubToken) }
        }
        .onChange(of: showingImportResults) { _, shown in
            if shown { model.holdFileImportPresentation(importResultsToken) }
        }
        .onChange(of: model.fileImportRequested) { _, requested in
            if requested { showingSources = false; showingImportResults = false }
        }
        .sheet(isPresented: $showingSources, onDismiss: {
            model.releaseFileImportPresentation(importHubToken)
        }) { ImportHubView().environmentObject(model).tint(Theme.accent) }
        .sheet(isPresented: $showingImportResults, onDismiss: {
            model.releaseFileImportPresentation(importResultsToken)
        }) { NavigationStack { ImportResultsView() }.environmentObject(model).tint(Theme.accent) }

    }

    private var shelfWithMoveSheet: some View {
        shelfNavigation
        .sheet(isPresented: $moving, onDismiss: { moveSelection = [] }) {
            GroupPickerView(count: moveSelection.count, parentGroup: group) { path in
                let ids = moveSelection
                model.move(ids, toGroup: path)
                if ids.allSatisfy({ id in
                    guard let updated = model.entries.first(where: { $0.id == id }) else { return false }
                    return updated.group == path
                }) {
                    finishEditing()
                }
            }
            .environmentObject(model)
            .presentationDetents([.medium, .large])
        }
    }

    private var shelfWithRenameAlert: some View {
        shelfWithMoveSheet
        .alert("重命名分组", isPresented: showingRename) {
            TextField("分组名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let old = renaming {
                    let parent = old.split(separator: "/").dropLast().joined(separator: "/")
                    model.renameGroup(old, to: parent.isEmpty ? renameText : parent + "/" + renameText)
                }
                renaming = nil
            }
        }
    }

    private var shelfWithBookRemoval: some View {
        shelfWithRenameAlert
        .confirmationDialog("删除 \(removalSelection.count) 本书的本机副本？", isPresented: $removing, titleVisibility: .visible, presenting: Optional(removalSelection)) { (ids: Set<String>) in
            Button("删除本机副本", role: .destructive) { removeSelectedBooks(ids) }
            Button("取消", role: .cancel) { removalSelection = [] }
        } message: { (_: Set<String>) in
            Text("已有的 iCloud 备份会保留。示例书籍不会删除；没有备份的本机文件需重新导入。")
        }
    }

    private var shelfWithGroupRemoval: some View {
        shelfWithBookRemoval
        .confirmationDialog("删除这个分组？", isPresented: showingGroupRemoval, titleVisibility: .visible, presenting: dissolvingGroup) { (path: String) in
            Button("删除分组", role: .destructive) {
                model.dissolveGroup(path)
                dissolvingGroup = nil
            }
            Button("取消", role: .cancel) { dissolvingGroup = nil }
        } message: { (_: String) in Text("书籍会保留，并移回上一级分组。") }
    }

    private var observedShelf: some View {
        shelfWithGroupRemoval
        .onChange(of: removing) { _, presented in if !presented { removalSelection = [] } }
        .onChange(of: query) { _, _ in selection = [] }
        .onChange(of: searching) { _, presented in if !presented { searchFocused = false } }
        .onChange(of: filter) { _, _ in selection = [] }
        .onChange(of: category) { _, _ in selection = [] }
        .onChange(of: kind) { _, _ in
            finishEditing()
            category = nil
            filter = "全部"
            query = ""
            searching = false
        }
        .onChange(of: sorted.map(\.id)) { _, ids in selection.formIntersection(Set(ids)) }
        .onChange(of: model.tab) { _, tab in
            if tab != 0 { finishEditing(); searching = false }
            else { consumeSearchRequest() }
        }
        .onAppear(perform: consumeSearchRequest)
        .onChange(of: model.shelfSearchRequested) { _, _ in consumeSearchRequest() }
    }

    private var showingRename: Binding<Bool> {
        Binding<Bool>(get: { renaming != nil }, set: { presented in
            if !presented { renaming = nil }
        })
    }

    private var showingGroupRemoval: Binding<Bool> {
        Binding<Bool>(get: { dissolvingGroup != nil }, set: { presented in
            if !presented { dissolvingGroup = nil }
        })
    }

    private var summary: String {
        var parts: [String] = []
        if !folders.isEmpty { parts.append("\(folders.count) 个分组") }
        parts.append("\(sorted.count) 本书")
        return parts.joined(separator: " · ")
    }

    private var shelfSubtitle: String {
        "\(model.visibleEntries.filter { !$0.isComic }.count) 本书 · \(model.visibleEntries.filter(\.isComic).count) 本漫画"
    }

    private var shelfHeader: some View {
        Masthead(title: "书房", subtitle: todayReadingText,
                 kicker: "\(todayDateText) · 书刊", issue: "\(model.visibleEntries.count) VOL.",
                 actionTitle: "搜索", action: startSearch)
    }

    /// 「书房」页眉副行：日期 · 星期 + 今日已读时长。
    private var studySubtitle: String { "\(todayDateText) · \(todayReadingText)" }

    private static let studyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private var todayDateText: String {
        let now = Date()
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = weekdays[max(0, min(6, Calendar.current.component(.weekday, from: now) - 1))]
        return "\(Self.studyDateFormatter.string(from: now)) · \(weekday)"
    }

    /// 今日已读口径与统计同源：visibleSessions 中 start 落在今日的 seconds 汇总。
    private var todayReadingText: String {
        let calendar = Calendar.current
        let seconds = model.visibleSessions.filter { calendar.isDateInToday($0.start) }.reduce(0) { $0 + $1.seconds }
        let minutes = Int(seconds / 60)
        guard minutes > 0 else { return "今日还没开始读" }
        return minutes >= 60 ? "今日已读 \(minutes / 60) 小时 \(minutes % 60) 分钟" : "今日已读 \(minutes) 分钟"
    }

    /// 正在读大卡选书，与 StudyRootView 启动自动打开同一口径：最近在读优先，
    /// 其次第一本本地非漫画，再其次第一本本地书；lastReadingBook 本身不排除漫画（用户正在读的优先）。
    private var heroEntry: ShelfEntry? {
        model.lastReadingBook
            ?? model.visibleEntries.first { $0.local && !$0.isComic }
            ?? model.visibleEntries.first { $0.local }
    }

    /// 今日一句数据源：全部可见书目的划线按 date 取最新一条（划线存于各书 entry.highlights，时间字段为 date）。
    private var latestHighlight: Highlight? {
        model.visibleEntries.flatMap { $0.highlights ?? [] }.max { $0.date < $1.date }
    }

    private func heroCard(_ entry: ShelfEntry) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: Theme.space4) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "正在读")
                    Spacer(minLength: Theme.space2)
                    SealBadge(text: entry.format.uppercased())
                }
                // 封面宽度是书封排版尺寸，沿用详情页的 104pt。
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space4))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.space4))
                layout {
                    CoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 104)
                    VStack(alignment: .leading, spacing: Theme.space2) {
                        Text(entry.title)
                            .accessibilityIdentifier("study.heroTitle")
                            .accessibilityLabel(entry.title)
                            .font(Theme.serif(20)).foregroundStyle(Theme.ink)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        Text(entry.author.isEmpty ? entry.format : entry.author)
                            .font(Theme.sans(13)).foregroundStyle(Theme.ink3)
                        if entry.started, entry.chapterCount > 0 {
                            let chapter = "第 \(min(max(1, entry.progress.chapter + 1), max(1, entry.chapterCount))) / \(entry.chapterCount) \(entry.isComic ? "页" : "章")"
                            Text(chapter).font(Theme.sans(13)).monospacedDigit().foregroundStyle(Theme.ink3)
                                .accessibilityIdentifier("study.heroChapter").accessibilityLabel(chapter)
                        }
                        heroProgress(entry)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                adaptiveRow {
                    PrimaryButton(entry.started ? "继续阅读" : "开始阅读") {
                        Haptics.light()
                        model.open(entry)
                    }
                    .accessibilityIdentifier("study.heroContinue")
                    SecondaryButton("开始专注") {
                        // 漫画沿用直接打开行为，不写专注直达键。
                        if !entry.isComic { UserDefaults.standard.set(entry.id, forKey: "study.openFocus.bookID") }
                        Haptics.light()
                        model.open(entry)
                    }
                    .accessibilityIdentifier("study.heroFocus")
                }
            }
        }
    }

    @ViewBuilder
    private func heroProgress(_ entry: ShelfEntry) -> some View {
        ProgressLine(value: entry.started ? entry.readFraction : 0)
        if !entry.started {
            Text("还没开始读").font(.caption).foregroundStyle(Theme.ink3)
        } else if entry.readFraction >= 0.995 {
            Text("已读完").font(.caption).foregroundStyle(Theme.accent)
        } else {
            HStack(spacing: Theme.space2) {
                Text(entry.percentText)
                    .font(.caption2).foregroundStyle(Theme.ink2).monospacedDigit()
            }
            .padding(.top, Theme.space1)
        }
    }

    /// 保留最新划线数据源，以刊物扉页引文呈现；不改变每日摘句的轮换规则。
    private func todayQuote(_ highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text("FOLIO QUOTE · 摘录")
                .font(Theme.masthead).tracking(Theme.mastheadTracking)
                .foregroundStyle(Theme.accent)
            Text(highlight.text).font(Theme.serif(19)).lineSpacing(5).foregroundStyle(Theme.ink)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
            if let entry = model.visibleEntries.first(where: { ($0.highlights ?? []).contains(where: { $0.id == highlight.id }) }) {
                Text("——《\(entry.title)》 · \(entry.author.isEmpty ? "佚名" : entry.author)")
                    .font(Theme.sans(13)).foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.space3)
        .padding(.horizontal, Theme.space4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.rule) }
        .overlay(alignment: .leading) { Rectangle().fill(Theme.clay).frame(width: 4).accessibilityHidden(true) }
    }

    /// v29 导入收敛：唯一的「添书」入口，直接打开 ImportHub（含文件导入、传书方式与最近导入结果）。
    private var addBooksMenu: some View {
        Button { searching = false; showingSources = true } label: {
            Label { Text("添书") } icon: { ThemeIcon(symbol: Icon.add) }
                .font(Theme.sans(15, weight: .medium)).foregroundStyle(Theme.onInk)
                .padding(.horizontal, Theme.space4).frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("import.book")
        .accessibilityLabel("添书")
    }

    private var searchEntry: some View {
        Button(action: startSearch) {
            HStack(spacing: Theme.space2) {
                ThemeIcon(symbol: Icon.search, size: 19)
                    .foregroundStyle(Theme.ink2)
                Text(searchText.isEmpty ? "搜索书名、作者或分组" : searchText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.space4)
            .frame(minHeight: Theme.rowMinHeight)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.rule) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索所有分组中的\(kind == "comics" ? "漫画" : "书籍")")
        .accessibilityIdentifier("shelf.search")
    }

    private var kindSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.space2) {
                kindButton("书籍", value: "books")
                kindButton("漫画", value: "comics")
                Button { showingGroups.toggle() } label: {
                    Text("分组")
                }.buttonStyle(ChipPillStyle(selected: showingGroups)).accessibilityAddTraits(showingGroups ? .isSelected : [])
                libraryOptions
            }
        }
    }

    private func kindButton(_ title: String, value: String) -> some View {
        let selected = kind == value && !showingGroups
        let count = model.visibleEntries.filter { value == "comics" ? $0.isComic : !$0.isComic }.count
        return Button {
            Haptics.selection()
            withAnimation(Theme.pressSpring) { kind = value; category = nil; showingGroups = false }
        } label: {
            Text(L(title))
        }
        .buttonStyle(ChipPillStyle(selected: selected))
        .accessibilityLabel("\(title)，\(count) 本")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var shelfControls: some View {
        if editing {
            adaptiveRow {
                VStack(alignment: .leading, spacing: Theme.space1) {
                    Text("已选择 \(selection.count) 本书").font(Theme.serif(20)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    Text(summary).font(.caption).foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: Theme.space2)
                Button(selection == Set(sorted.map(\.id)) && !sorted.isEmpty ? "取消全选" : "全选") {
                    selection = selection == Set(sorted.map(\.id)) ? [] : Set(sorted.map(\.id))
                }
                .font(.subheadline.weight(.medium)).frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
                .disabled(sorted.isEmpty).accessibilityIdentifier("shelf.selectAll")
            }
        } else {
            viewOptions
            if hasFilters || !searchText.isEmpty {
                Text("\(!searchText.isEmpty ? "搜索结果" : "筛选结果") · \(summary)")
                    .font(.caption).foregroundStyle(Theme.ink3).padding(.top, Theme.space1)
            }
        }
    }

    private var scopeNotice: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            if editing {
                Text(isRoot ? "可跨分组选择。选好后用下方操作整理；新建分组在「移动分组」中。" : "选择本分组的书籍后，在下方移动、隐藏或删除。")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
            if !searchText.isEmpty && !searching {
                Label { Text(kind == "comics" ? "正在搜索所有分组中的漫画" : "正在搜索所有分组中的书籍") } icon: { ThemeIcon(symbol: Icon.search) }
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }
            if hasFilters {
                HStack(spacing: Theme.space2) {
                    Text([filter == "全部" ? nil : filter, category].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Button("清除筛选") { filter = "全部"; category = nil }
                        .font(.caption.weight(.medium))
                        .frame(minHeight: Theme.iconButtonSize)
                        .accessibilityIdentifier("shelf.clearFilters")
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 浏览工具各司其职：筛选改变范围，排序改变顺序，显示改变呈现方式。
    private var viewOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.space2) {
                Text(searching ? "找到 \(sorted.count) 本书" : "全部 \(sorted.count)").font(.caption).foregroundStyle(Theme.ink2)
                Spacer(minLength: Theme.space1)
                if !searching { filterMenu; sortMenu; layoutMenu; organizeButton }
            }
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(summary).font(.caption).foregroundStyle(Theme.ink2)
                HStack(spacing: Theme.space2) { filterMenu; sortMenu; layoutMenu; organizeButton }
            }
        }
    }

    private var organizeButton: some View {
        Button("整理", action: beginEditing).font(.caption).foregroundStyle(Theme.accent)
            .frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize).disabled(visibleKindEntries.isEmpty)
            .accessibilityLabel("整理书库").accessibilityIdentifier("shelf.organize")
    }

    private var filterMenu: some View {
        Menu {
            Picker("阅读状态", selection: $filter) {
                Text("全部状态").tag("全部")
                Text("在读").tag("在读")
                Text("待读").tag("未开卷")
                Text("读完").tag("读完")
            }
            Picker("分类", selection: $category) {
                Text("全部分类").tag(String?.none)
                ForEach(categories, id: \.self) { Text($0).tag(Optional($0)) }
            }
            if hasFilters { Button("清除筛选") { filter = "全部"; category = nil } }
        } label: {
            optionLabel(Icon.filter, hasFilters ? "筛选 · \((filter == "全部" ? 0 : 1) + (category == nil ? 0 : 1))" : "筛选")
                .foregroundStyle(hasFilters ? Theme.accent : Theme.ink2)
        }
        .accessibilityLabel("筛选书籍")
        .accessibilityValue(hasFilters ? [filter == "全部" ? nil : filter, category].compactMap { $0 }.joined(separator: "，") : "全部状态与分类")
        .accessibilityIdentifier("shelf.filter")
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序", selection: $model.sortOrder) {
                // 原生菜单的选项使用 Text，避免自定义图标视图使系统菜单丢失标题。
                Text("最近阅读").tag("recent")
                Text("书名").tag("title")
                Text("作者").tag("author")
                Text("添加时间").tag("added")
                Text("手动排序").tag("manual")
            }
        } label: { optionLabel(Icon.sort, "排序") }
        .foregroundStyle(Theme.ink2)
        .accessibilityLabel("排序：\(sortLabel)")
        .accessibilityIdentifier("shelf.sort")
    }

    private var layoutMenu: some View {
        Menu {
            if typeSize.isAccessibilitySize {
                Text("大字号下使用列表，原有显示偏好保持不变。")
            } else {
                Picker("显示方式", selection: $layout) {
                    Text("封面网格").tag("grid")
                    Text("书目列表").tag("list")
                }
            }
        } label: { optionLabel(useList ? Icon.list : Icon.grid, "视图") }
        .foregroundStyle(Theme.ink2)
        .accessibilityLabel("显示方式：\(useList ? "列表" : "网格")")
        .accessibilityHint(typeSize.isAccessibilitySize ? "大字号下使用列表，原有显示偏好保持不变" : "切换封面网格或书目列表")
        .accessibilityIdentifier("shelf.layout")
    }

    private func optionLabel(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.space1) {
            ThemeIcon(symbol: icon).accessibilityHidden(true)
            Text(L(text))
        }
        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.space3).frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .overlay { RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.line, lineWidth: Theme.rule) }
        .contentShape(Rectangle())
    }

    private var libraryOptions: some View {
        Menu {
            if model.hiddenUnlocked {
                Button { model.hiddenUnlocked = false } label: { Label { Text("收起隐藏书籍") } icon: { ThemeIcon(symbol: Icon.visibilityAction(currentlyVisible: true)) } }
            } else {
                Button { Task { await model.unlockHidden() } } label: { Label { Text("显示隐藏书籍") } icon: { ThemeIcon(symbol: Icon.visibilityAction(currentlyVisible: false)) } }
            }
        } label: {
            Label { Text("更多") } icon: { ThemeIcon(symbol: Icon.more) }.font(.caption)
                .foregroundStyle(Theme.ink2).frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize).contentShape(Rectangle())
        }
        .accessibilityLabel("更多书架操作")
        .accessibilityIdentifier("shelf.more")
    }

    // MARK: 主入口：添加、搜索、整理

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if editing {
            ToolbarItem(placement: .topBarTrailing) {
                Button("取消整理", action: finishEditing)
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: Theme.iconButtonSize)
                    .accessibilityIdentifier("shelf.finishOrganizing")
            }
        } else if !isRoot {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { searching = false; showingSources = true } label: {
                    Text("添书").font(.subheadline.weight(.medium)).frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
                }
                .accessibilityIdentifier("import.book")
                .accessibilityLabel("添书")
                // 搜索框已常驻在正文顶部，导航栏只保留添加与整理
                Button(action: beginEditing) {
                    Text("整理").font(.subheadline.weight(.medium)).frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
                }
                .disabled(visibleKindEntries.isEmpty)
                .accessibilityIdentifier("shelf.organize")
                libraryOptions
            }
        }
    }

    private var shelfSearchBar: some View {
        VStack(alignment: .leading, spacing: Theme.space4) {
            EditorialIntro(title: "搜索书库", detail: "在所有分组中查找书名、作者与分类", eyebrow: "查找")
            HStack(spacing: Theme.space2) {
                HStack(spacing: Theme.space2) {
                    ThemeIcon(symbol: Icon.search, size: 22)
                        .foregroundStyle(Theme.ink3)
                    TextField("书名、作者、分类或分组", text: $query)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onSubmit { rememberSearch(); searchFocused = false }
                        .accessibilityLabel(kind == "comics" ? "搜索所有分组中的漫画" : "搜索所有分组中的书籍")
                        .accessibilityIdentifier("shelf.search-field")
                    if !query.isEmpty {
                        Button { query = ""; searchFocused = true } label: {
                            ThemeIcon(symbol: Icon.clearText)
                                .foregroundStyle(Theme.ink3)
                                .frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索文字")
                    }
                }
                .padding(.leading, Theme.space4)
                .padding(.trailing, query.isEmpty ? Theme.space4 : 0)
                .frame(minHeight: Theme.rowMinHeight)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                Button("取消", action: cancelSearch)
                    .font(.subheadline)
                    .frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
            }
            Text(kind == "comics" ? "搜索所有分组中的漫画" : "搜索所有分组中的书籍")
                .font(.caption)
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
        .onAppear { searchFocused = true }
    }

    private func consumeSearchRequest() {
        guard isRoot, model.tab == 0, model.shelfSearchRequested else { return }
        model.shelfSearchRequested = false
        startSearch()
    }

    private func startSearch() {
        showingGroups = false
        filter = "全部"
        category = nil
        searching = true
        searchFocused = true
    }

    private func cancelSearch() {
        rememberSearch()
        searchFocused = false
        searching = false
        query = ""
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            if !savedSearches.isEmpty {
                HStack {
                    SectionHeader(title: "最近搜索")
                    Spacer()
                    Button("清空") { savedSearches = "" }.font(.caption).frame(minHeight: Theme.iconButtonSize)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.space2) {
                        ForEach(savedSearches.split(separator: "\n").map(String.init), id: \.self) { term in
                            Button { query = term; searchFocused = false } label: {
                                Text(term).font(.caption).foregroundStyle(Theme.ink2).padding(.horizontal, Theme.space4).padding(.vertical, Theme.space3)
                                    .background(Theme.surface2, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("搜索覆盖所有分组。隐藏书籍需验证后查看。")
                .font(.caption).foregroundStyle(Theme.ink2).padding(Theme.space4).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    private func rememberSearch() {
        let term = searchText
        guard !term.isEmpty else { return }
        let previous = savedSearches.split(separator: "\n").map(String.init).filter { $0 != term }
        savedSearches = ([term] + previous).prefix(6).joined(separator: "\n")
    }

    // MARK: 空态

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            EmptyState(title: "没有符合条件的书", detail: "换个关键词，或调整筛选。")
        } else if kind == "comics" && isRoot && visibleKindEntries.isEmpty {
            EmptyState(title: "还没有漫画", detail: "导入 CBZ 或图片 ZIP 压缩包，会在这里以漫画模式阅读。",
                       actionTitle: "导入漫画") { showingSources = true }
        } else if model.entries.isEmpty {
            EmptyState(title: "从第一本书开始", detail: "支持 EPUB、TXT、PDF、MOBI、AZW3、CBZ 与听页备份，也可使用 WiFi 传书、WebDAV 或 OPDS。",
                       actionTitle: "导入书籍") { showingSources = true }
        } else {
            EmptyState(title: isRoot ? "没有符合条件的书" : "这个分组是空的",
                       detail: isRoot ? "换个关键词，或调整筛选。" : "回到书库点右上角「整理」，选择书籍后通过「移动分组」移入这里。")
        }
    }

    // MARK: 网格（书阁陈列）

    // 书封保留原固定比例与列表 60pt 排版宽度；其余布局尺寸使用 Theme 令牌。
    private var bookGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.space3, alignment: .top), GridItem(.flexible(), spacing: Theme.space3, alignment: .top)], alignment: .leading, spacing: Theme.space5) {
            ForEach(folders, id: \.self) { path in
                VStack(alignment: .leading, spacing: 0) {
                    NavigationLink { ShelfView(group: path) } label: { folderTile(path) }
                        .buttonStyle(PressButtonStyle())
                        .contextMenu { folderMenu(path) }
                    folderActions(path)
                }
            }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, entry in
                bookCell(entry) { gridTile(entry, index: index + 1) }
            }
        }
    }

    @ViewBuilder
    private func bookCell<Content: View>(_ entry: ShelfEntry, @ViewBuilder label: () -> Content) -> some View {
        if editing {
            Button { toggle(entry.id) } label: {
                HStack(spacing: Theme.space4) {
                    ThemeIcon(symbol: Icon.selection(selection.contains(entry.id)))
                        .font(.system(size: 22)).foregroundStyle(selection.contains(entry.id) ? Theme.ink : Theme.ink3)
                    label()
                }
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityLabel("\(selection.contains(entry.id) ? "取消选择" : "选择")《\(entry.title)》")
            .accessibilityAddTraits(selection.contains(entry.id) ? .isSelected : [])
        } else if useList || searching {
            adaptiveRow {
                readingButton(entry, label: label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                detailLink(entry).padding(.leading, Theme.space1)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                readingButton(entry, label: label)
                RowDivider().padding(.top, Theme.space2)
                detailLink(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .paperPanel(inset: Theme.cardInset)
        }
    }

    private func readingButton<Content: View>(_ entry: ShelfEntry, @ViewBuilder label: () -> Content) -> some View {
        Button {
            Haptics.light()
            rememberSearch()
            searching = false
            model.open(entry)
        } label: { label() }
        .buttonStyle(PressButtonStyle())
        .accessibilityIdentifier("book." + entry.id)
        .accessibilityLabel("\(entry.started ? "继续阅读" : "开始阅读")《\(entry.title)》")
        .accessibilityValue([readingSummary(entry), lastReadLabel(entry)].compactMap { $0 }.joined(separator: "，"))
        .accessibilityHint("轻点翻开正文；书籍信息与管理请使用旁边的详情按钮")
        .contextMenu { menu(entry) }
    }

    private func detailLink(_ entry: ShelfEntry) -> some View {
        NavigationLink { BookDetailView(entryID: entry.id) } label: {
            HStack(spacing: Theme.space2) {
                if !useList {
                    Text(entry.local ? (entry.started ? entry.percentText : "待读") : "iCloud")
                        .font(Theme.kicker).tracking(1)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                    Spacer(minLength: 0)
                }
                Text("详情").font(.caption).foregroundStyle(Theme.accent)
                ThemeIcon(symbol: Icon.disclosure).font(.caption2).foregroundStyle(Theme.ink3)
            }
            .frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看《\(entry.title)》详情与管理")
        .accessibilityIdentifier("book.detail." + entry.id)
    }

    private func toggle(_ id: String) {
        Haptics.selection()
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func booksInCurrentKind(_ path: String) -> [ShelfEntry] {
        model.books(inGroup: path).filter { kind == "comics" ? $0.isComic : !$0.isComic }
    }

    /// 分组预览与当前书籍 / 漫画类型保持一致。
    private func folderTile(_ path: String) -> some View {
        let books = booksInCurrentKind(path)
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.aspectRatio(0.75, contentMode: .fit).overlay {
                GeometryReader { geo in
                    let w = (geo.size.width - Theme.space3 * 2 - Theme.space2) / 2
                    LazyVGrid(columns: [GridItem(.fixed(w), spacing: Theme.space2), GridItem(.fixed(w), spacing: Theme.space2)], spacing: Theme.space2) {
                        ForEach(books.prefix(4)) { book in
                            CoverView(title: book.title, color: book.color, image: model.covers[book.id], width: w)
                        }
                    }
                    .padding(Theme.space3)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .paperPanel(inset: 0)
            .padding(.bottom, Theme.space3)
            HStack(spacing: Theme.space1) {
                ThemeIcon(symbol: Icon.folder, size: 12)
                    .foregroundStyle(Theme.ink2)
                Text(String(path.split(separator: "/").last ?? ""))
                    .font(Theme.serif(17))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .padding(.top, Theme.space2)
            Text("\(books.count) 本书")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.ink3)
                .padding(.top, Theme.space1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("分组 \(path)，\(books.count) 本")
    }

    @ViewBuilder
    private func folderMenu(_ path: String) -> some View {
        Button { renameText = String(path.split(separator: "/").last ?? ""); renaming = path } label: { Label { Text("重命名") } icon: { ThemeIcon(symbol: Icon.edit) } }
        Button(role: .destructive) { dissolvingGroup = path } label: { Label { Text("删除分组（保留书籍）") } icon: { ThemeIcon(symbol: Icon.folderRemove) } }
    }

    private func folderActions(_ path: String) -> some View {
        Menu { folderMenu(path) } label: {
            Label { Text("管理") } icon: { ThemeIcon(symbol: Icon.moreCircle) }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.ink2)
                .frame(minWidth: Theme.rowMinHeight, minHeight: Theme.iconButtonSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("管理分组 \(path)")
    }

    private func gridTile(_ entry: ShelfEntry, index: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FlexibleCover(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], index: index)
                .overlay(alignment: .topLeading) {
                    if entry.isHidden {
                        SealBadge(text: "已隐藏", color: Theme.ink2, background: Theme.surface)
                            .padding(Theme.space2)
                            .accessibilityLabel("已隐藏")
                    }
                }
            Text(entry.title)
                .font(Theme.serif(17))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .padding(.top, Theme.space2)
            gridProgress(entry)
                .padding(.top, Theme.space1)
            if let lastRead = lastReadLabel(entry) {
                Text(lastRead)
                    .font(.caption2).foregroundStyle(Theme.ink2)
                    .lineLimit(1).padding(.top, Theme.space1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 列表行副行：作者 · 总章数（漫画按页计）。
    private func listSubtitle(_ entry: ShelfEntry) -> String {
        var parts = [entry.author.isEmpty ? "佚名" : entry.author]
        if entry.chapterCount > 0 { parts.append("\(entry.chapterCount) \(entry.isComic ? "页" : "章")") }
        if entry.local && entry.started { parts.append(entry.percentText) }
        return parts.joined(separator: " · ")
    }

    /// 列表与网格都以文字区分未读、在读、读完；进度线集中在正在读大卡。
    @ViewBuilder
    private func listProgress(_ entry: ShelfEntry) -> some View {
        if !entry.local {
            Text("iCloud 藏书").font(Theme.sans(13)).foregroundStyle(Theme.ink3)
        } else if !entry.started {
            Text("未读").font(Theme.sans(13)).foregroundStyle(Theme.ink3)
        } else if entry.readFraction >= 0.995 {
            Text("读完").font(Theme.sans(13)).foregroundStyle(Theme.clayDeep)
        } else {
            SealDot(text: "在读")
        }
    }

    private func gridProgress(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.space1) {
            Text(listSubtitle(entry)).font(Theme.sans(13)).monospacedDigit().foregroundStyle(Theme.ink3)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            listProgress(entry)
        }
    }

    /// 阅读位置与最近时间来自阅读记录；播放、暂停和跳句不会改变这里的展示。
    private func readingSummary(_ entry: ShelfEntry) -> String {
        guard entry.local else { return "iCloud 藏书" }
        guard entry.started else { return "待读" }
        if entry.readFraction >= 0.995 { return "已读完" }
        let unit = entry.isComic ? "页" : "章"
        let chapter = min(max(1, entry.progress.chapter + 1), max(1, entry.chapterCount))
        return "已读 \(entry.percentText) · 第 \(chapter) / \(max(1, entry.chapterCount)) \(unit)"
    }

    private func lastReadLabel(_ entry: ShelfEntry) -> String? {
        let timestamp = model.readingRecency(for: entry)
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: timestamp / 1_000)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天读过" }
        if calendar.isDateInYesterday(date) { return "昨天读过" }
        let format: Date.FormatStyle = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
            ? .dateTime.month().day() : .dateTime.year().month().day()
        return "上次阅读 · " + date.formatted(format)
    }

    // MARK: 列表（书目长卷）

    private var bookList: some View {
        LazyVStack(spacing: 0) {
            ForEach(folders, id: \.self) { path in
                HStack(spacing: 0) {
                    NavigationLink { ShelfView(group: path) } label: {
                        HStack(spacing: Theme.space4) {
                            ThemeIcon(symbol: Icon.folderFill)
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.ink)
                                .frame(width: Theme.iconButtonSize)
                            VStack(alignment: .leading, spacing: Theme.space1) {
                                Text(String(path.split(separator: "/").last ?? ""))
                                    .font(Theme.serif(17))
                                    .foregroundStyle(Theme.ink)
                                Text("\(booksInCurrentKind(path).count) 本书")
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink3)
                            }
                            Spacer(minLength: Theme.space2)
                        }
                        .frame(minHeight: Theme.rowMinHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle())
                    .contextMenu { folderMenu(path) }
                    folderActions(path).padding(.trailing, Theme.space3)
                }
                RowDivider()
            }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                HairlineRow {
                    bookCell(row) {
                        HStack(spacing: Theme.space4) {
                            CoverView(title: row.title, color: row.color, author: row.author, image: model.covers[row.id], width: 60)
                            VStack(alignment: .leading, spacing: Theme.space1) {
                                Text(row.title)
                                .font(Theme.serif(17))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                Text(listSubtitle(row))
                                .font(Theme.sans(13)).monospacedDigit()
                                .foregroundStyle(Theme.ink3)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                                if editing {
                                    Text(selection.contains(row.id) ? "已选择" : "未选择")
                                    .font(.caption).foregroundStyle(Theme.accent)
                                    .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    listProgress(row)
                                }
                                if !editing, let lastRead = lastReadLabel(row) {
                                    Text(lastRead)
                                    .font(.caption2).foregroundStyle(Theme.ink2)
                                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, Theme.space4)
                        .frame(minHeight: Theme.rowMinHeight)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .padding(.vertical, Theme.space1)
    }

    @ViewBuilder
    private func menu(_ entry: ShelfEntry) -> some View {
        Button { model.open(entry) } label: {
            Label { Text(entry.started ? "继续阅读" : "开始阅读") } icon: { ThemeIcon(symbol: Icon.read) }
        }
        if model.sortOrder == "manual" {
            Section("手动排序") {
                Button { ManualShelfOrder.move(entry.id, in: sorted, kind: kind, by: -1); model.objectWillChange.send() } label: { Label { Text("前移一位") } icon: { ThemeIcon(symbol: "arrow.up") } }
                Button { ManualShelfOrder.move(entry.id, in: sorted, kind: kind, by: 1); model.objectWillChange.send() } label: { Label { Text("后移一位") } icon: { ThemeIcon(symbol: "arrow.down") } }
                Button { ManualShelfOrder.move(entry.id, in: sorted, kind: kind, to: 0); model.objectWillChange.send() } label: { Label { Text("移到最前") } icon: { ThemeIcon(symbol: "arrow.up.to.line") } }
                Button { ManualShelfOrder.move(entry.id, in: sorted, kind: kind, to: .max); model.objectWillChange.send() } label: { Label { Text("移到最后") } icon: { ThemeIcon(symbol: "arrow.down.to.line") } }
            }
        }
        if !entry.isComic {
            Button {
                if model.player.book?.id == entry.id { model.showingPlayer = true }
                else { model.listen(entry.id) }
            } label: {
                Label { Text(model.player.book?.id == entry.id ? "打开播放器" : "听书") } icon: { ThemeIcon(symbol: Icon.listen) }
            }
        }
        Divider()
        Button { moveSelection = [entry.id]; moving = true } label: { Label { Text("移动分组 / 新建分组") } icon: { ThemeIcon(symbol: Icon.folder) } }
        Button { model.setHidden([entry.id], !entry.isHidden) } label: {
            Label { Text(entry.isHidden ? "取消隐藏" : "隐藏") } icon: { ThemeIcon(symbol: Icon.visibilityAction(currentlyVisible: !entry.isHidden)) }
        }
    }

    // MARK: 多选操作

    private var editBar: some View {
        VStack(spacing: Theme.space2) {
            HStack {
                Text("已选择 \(selection.count) 本")
                    .font(Theme.sans(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer()
                if !selection.isEmpty && removableSelection.isEmpty {
                    Text("示例书籍可分组或隐藏")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink3)
                }
            }
            .padding(.horizontal, Theme.space3)
            HStack(spacing: Theme.space2) {
                editButton("移动分组", Icon.folder, disabled: selection.isEmpty) {
                    moveSelection = selection
                    moving = true
                }.accessibilityIdentifier("shelf.move")
                editButton(allSelectedHidden ? "取消隐藏" : "隐藏", Icon.visibilityAction(currentlyVisible: !allSelectedHidden), disabled: selection.isEmpty, action: hideSelectedBooks)
                    .accessibilityIdentifier("shelf.hide")
                editButton("删除", Icon.delete, destructive: true, disabled: removableSelection.isEmpty) {
                    removalSelection = removableSelection
                    removing = true
                }.accessibilityIdentifier("shelf.delete")
            }
        }
        .padding(Theme.space3)
        .floatingPanel(cornerRadius: Theme.radius)
        .padding(.horizontal, Theme.space4)
        .padding(.bottom, Theme.space2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func editButton(_ title: String, _ icon: String, destructive: Bool = false, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.space1) {
                ThemeIcon(symbol: icon).font(.system(size: 18))
                Text(L(title)).font(.caption.weight(.medium)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(destructive ? Theme.danger : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight)
            .background(destructive ? Theme.dangerSoft : Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? Theme.disabledOpacity : 1)
    }

    private func beginEditing() {
        Haptics.selection()
        searching = false
        selection = []
        moveSelection = []
        removalSelection = []
        editing = true
    }

    private func finishEditing() {
        selection = []
        moveSelection = []
        removalSelection = []
        moving = false
        removing = false
        editing = false
    }

    private func hideSelectedBooks() {
        let ids = selection
        let hiding = !allSelectedHidden
        model.setHidden(ids, hiding)
        if ids.allSatisfy({ id in model.entries.first { $0.id == id }?.isHidden == hiding }) {
            finishEditing()
            if hiding && !model.hiddenUnlocked {
                model.notify("已隐藏 \(ids.count) 本书。可在书架「更多」或设置中验证身份后显示。")
            }
        }
    }

    private func removeSelectedBooks(_ ids: Set<String>) {
        var failures: [String] = []
        var failedIDs: Set<String> = []
        for id in ids {
            let title = model.entries.first { $0.id == id }?.title ?? "书籍"
            do { try model.removeLocal(id) }
            catch { failures.append("《\(title)》：\(error.localizedDescription)"); failedIDs.insert(id) }
        }
        removalSelection = []
        if failures.isEmpty { finishEditing() }
        else {
            selection = failedIDs.intersection(Set(model.entries.map(\.id)))
            model.message = "部分书籍未能删除：\n" + failures.joined(separator: "\n")
        }
    }

}

// MARK: - 选择分组

/// 先选书，再选择现有分组或新建并立即移入；取消不保留待创建状态。
struct GroupPickerView: View {
    let count: Int
    var parentGroup: String? = nil
    let onPick: (String?) -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    private var targetPath: String {
        let clean = AppModel.normalizedGroup(name)
        guard !clean.isEmpty else { return "" }
        return (parentGroup.map { $0 + "/" } ?? "") + clean
    }
    var body: some View {
        NavigationStack {
            List {
                Masthead(title: "给书找个位置", subtitle: "已选择 \(count) 本书。选择已有分组，或新建一个。", titleSize: 28)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section {
                    PaperCard {
                        VStack(alignment: .leading, spacing: Theme.space3) {
                            TextField("分组名称，可用 / 创建多级分组", text: $name)
                            .submitLabel(.done)
                            .onSubmit(create)
                            .padding(.horizontal, Theme.space3)
                            .frame(minHeight: Theme.rowMinHeight)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusField))
                            .overlay { RoundedRectangle(cornerRadius: Theme.radiusField).strokeBorder(Theme.lineField, lineWidth: Theme.rule) }
                            Button(action: create) {
                                Label { Text(model.groupPaths.contains(targetPath) ? "移入这个分组" : "新建并移入") } icon: { ThemeIcon(symbol: Icon.folderAdd) }
                                .frame(minHeight: Theme.iconButtonSize)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(targetPath.isEmpty || count == 0)
                        }
                    }
                } header: { Text("新建分组") } footer: {
                    Text(parentGroup.map { "在「\($0)」内创建，并移入已选的 \(count) 本书。" } ?? "创建后立即移入已选的 \(count) 本书。取消不会创建空分组。")
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section("移动到已有位置") {
                    Button { pick(nil) } label: {
                        HairlineRow(title: "书库首页 · 不分组", symbol: Icon.unfiled)
                    }
                    ForEach(model.groupPaths, id: \.self) { path in
                        Button { pick(path) } label: {
                            HairlineRow(title: path, symbol: Icon.folder)
                        }
                    }
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tint(Theme.clayDeep)
            .environment(\.defaultMinListRowHeight, Theme.rowMinHeight)
            .background(Theme.bg)
            .navigationTitle("移动 \(count) 本书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.frame(minHeight: Theme.iconButtonSize)
                }
            }
        }
    }
    private func create() {
        guard !targetPath.isEmpty, count > 0 else { return }
        pick(targetPath)
    }
    private func pick(_ path: String?) { onPick(path); dismiss() }
}

// MARK: - 导入（书库与书源共用）

struct FileImportRequest: Identifiable {
    let id = UUID()
    let multiple: Bool
}

/// UIKit's delegate delivers the selected copy immediately; sheet dismissal is not a URL mailbox.
@MainActor
struct LocalBookPicker: UIViewControllerRepresentable {
    var multiple = false
    let completion: ([URL]?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        makeDocumentPicker(delegate: context.coordinator)
    }
    func makeDocumentPicker(delegate: Coordinator) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.delegate = delegate
        picker.view.accessibilityIdentifier = "import.documentPicker"
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: ([URL]?) -> Void
        private(set) var completed = false
        init(completion: @escaping ([URL]?) -> Void) { self.completion = completion }
        func deliver(_ urls: [URL]?) {
            guard !completed else { return }
            completed = true
            completion(urls)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { deliver(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { deliver(nil) }
    }
}

/// 最近一批导入的逐项结果。失败文件重新选择，避免复用已经失效的安全作用域 URL。
struct ImportResultsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PaperBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    HStack {
                        Masthead(title: "导入结果", subtitle: "每个文件的状态，清楚记在这里。", titleSize: 28)
                        CircleIconButton(systemName: Icon.close, label: "关闭导入结果") { dismiss() }
                    }
                    if let report = model.importReport {
                        if report.finished {
                            EmptyState(
                                title: report.successes == 0 ? "这批文件未能导入" : "成功的书籍已加入书库",
                                detail: report.failures > 0 ? "请查看逐项原因，再重新选择需要处理的文件。成功项会保留。" : "文件已保存到本机书库，可以开始阅读了。",
                                state: report.successes == 0 ? .error : .success,
                                badge: report.failures > 0 ? "\(report.successes) 本成功，\(report.failures) 本需要处理" : "\(report.successes) 本书导入成功")
                        } else {
                            PaperCard {
                                VStack(alignment: .leading, spacing: Theme.space4) {
                                    SectionHeader(title: "正在导入书籍")
                                    HStack {
                                        Text("全部 \(report.items.count) 个文件 · 已处理 \(report.completed) 个")
                                            .font(Theme.sans(13)).foregroundStyle(Theme.ink3)
                                        Spacer(minLength: Theme.space2)
                                        Text("\(Int(Double(report.completed) / Double(max(1, report.items.count)) * 100))%")
                                            .font(Theme.sans(13)).monospacedDigit().foregroundStyle(Theme.ink2)
                                    }
                                    ProgressLine(value: Double(report.completed) / Double(max(1, report.items.count)))
                                }
                            }
                        }
                        LazyVStack(spacing: 0) {
                            ForEach(report.items) { item in
                                HairlineRow {
                                    HStack(alignment: .top, spacing: Theme.space3) {
                                        resultIcon(item)
                                        VStack(alignment: .leading, spacing: Theme.space1) {
                                            Text(item.name).font(Theme.serif(17)).foregroundStyle(Theme.ink)
                                                .fixedSize(horizontal: false, vertical: true)
                                            resultDescription(item)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, Theme.space3)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        if report.finished {
                            VStack(spacing: Theme.space3) {
                                SecondaryButton(report.failures > 0 ? "重新选择失败文件" : "继续导入文件") { model.requestFileImport(); dismiss() }
                                    .disabled(model.busy).accessibilityIdentifier("import.retrySelection")
                                PrimaryButton("前往书库") { model.tab = 0; dismiss() }
                            }
                        }
                    } else {
                        EmptyState(title: "暂无导入记录", detail: "导入书籍后，可以在这里查看每个文件的状态。",
                                   actionTitle: "选择文件") { model.requestFileImport(); dismiss() }
                    }
                }
                .padding(.horizontal, Theme.inset).padding(.vertical, Theme.space5)
                .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    @ViewBuilder private func resultIcon(_ item: ImportItem) -> some View {
        switch item.state {
        case .waiting: ThemeIcon(symbol: Icon.duration).foregroundStyle(Theme.ink2)
        case .importing: ProgressView().tint(Theme.ink2)
        case .imported: ThemeIcon(symbol: Icon.markRead).foregroundStyle(Theme.ink2)
        case .failed: ThemeIcon(symbol: Icon.close).foregroundStyle(Theme.danger)
        }
    }
    @ViewBuilder private func resultDescription(_ item: ImportItem) -> some View {
        switch item.state {
        case .waiting: Text("等待导入").font(.caption).foregroundStyle(Theme.ink2)
        case .importing: Text("正在解析并保存").font(.caption).foregroundStyle(Theme.accent)
        case .imported: Text("已加入书库").font(.caption).foregroundStyle(Theme.ink2)
        case .failed(let reason): Text(reason).font(.caption).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ExportedBook: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


/// 书架手动排序：书籍与漫画各自保存一份顺序；不在顺序里的新书排在最前（按添加时间）。
enum ManualShelfOrder {
    static func key(_ kind: String) -> String { "shelf.manualOrder." + (kind == "comics" ? "comics" : "books") }
    static func saved(_ kind: String) -> [String] { UserDefaults.standard.stringArray(forKey: key(kind)) ?? [] }
    static func sorted(_ entries: [ShelfEntry], kind: String, order: [String]? = nil) -> [ShelfEntry] {
        let order = order ?? saved(kind)
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let fresh = entries.filter { rank[$0.id] == nil }.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }
        let known = entries.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
        return fresh + known
    }
    /// 移动后把当前看到的完整顺序写回（隐藏或其他分组里的书保持原相对位置，排在后面）。
    static func move(_ id: String, in visible: [ShelfEntry], kind: String, by offset: Int = 0, to target: Int? = nil) {
        var ids = visible.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        let destination = max(0, min(ids.count - 1, target ?? (from + offset)))
        ids.remove(at: from); ids.insert(id, at: destination)
        let rest = saved(kind).filter { !ids.contains($0) }
        UserDefaults.standard.set(ids + rest, forKey: key(kind))
    }
}
