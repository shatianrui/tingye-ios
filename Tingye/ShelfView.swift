import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 书库：清晰的书目、柔和的封面网格与可跨分组的搜索和整理。
struct ShelfView: View {
    /// 当前所在分组；nil 为书库根目录
    var group: String? = nil
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var widthClass
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
    private var adaptiveRow: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space2))
            : AnyLayout(HStackLayout(spacing: Theme.space3))
    }
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
        L(["title": "书名", "author": "作者", "added": "添加时间", "manual": "手动排序"][model.sortOrder] ?? "最近阅读")
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
            VStack(alignment: .leading, spacing: Theme.space3) {
                if searching {
                    shelfSearchBar
                } else if !editing {
                    if isRoot {
                        shelfHeader
                        if let heroEntry { continueStrip(heroEntry) }
                    } else {
                        VStack(alignment: .leading, spacing: Theme.space1) {
                            Text(title).font(IndexTheme.editorial(28, relativeTo: .title))
                                .foregroundStyle(IndexTheme.ink).accessibilityAddTraits(.isHeader)
                            Text(shelfSubtitle).font(.caption).foregroundStyle(IndexTheme.muted)
                        }
                        searchEntry
                    }
                }

                if searching && searchText.isEmpty { recentSearches }
                collection
                if searching && !searchText.isEmpty { recentSearches }
                if isRoot && !editing && !searching, let latestHighlight {
                    todayQuote(latestHighlight).padding(.top, Theme.space3)
                }
            }
            .padding(.horizontal, widthClass == .regular ? Theme.inset : Theme.space4)
            .padding(.top, searching ? Theme.space1 : Theme.space3)
            .padding(.bottom, Theme.space6)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            if isRoot && !editing && !searching { kindSelector }
            shelfControls
            if editing || hasFilters || (!searching && !searchText.isEmpty) { scopeNotice }
            if sorted.isEmpty && folders.isEmpty {
                emptyState
            } else if useList || editing || searching {
                bookList
            } else {
                bookGrid
            }
        }
    }

    private var shelfNavigation: some View {
        shelfContent
        .scrollDismissesKeyboard(.interactively)
        .background(IndexTheme.canvas.ignoresSafeArea())
        .navigationTitle(editing ? "整理书库" : (isRoot ? "" : title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbar(isRoot && !editing ? .hidden : .visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { if editing { editBar } }
        .toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: editing || searching)
        .animation(IndexTheme.transition, value: editing)
        .respectReducedMotion()
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

    private var shelfSubtitle: String {
        "\(model.visibleEntries.filter { !$0.isComic }.count) 本书 · \(model.visibleEntries.filter(\.isComic).count) 本漫画"
    }

    private var shelfHeader: some View {
        adaptiveRow {
        VStack(alignment: .leading, spacing: Theme.space1) {
            Text("书库").font(IndexTheme.editorial(34, relativeTo: .largeTitle))
                .foregroundStyle(IndexTheme.ink).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.month().day().weekday(.abbreviated))
                todayReadingLabel
            }
            .font(.subheadline).foregroundStyle(IndexTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.space2) {
                searchEntry
                addBookButton
            }
        }
    }

    /// 今日已读口径与统计同源：visibleSessions 中 start 落在今日的 seconds 汇总。
    private var todayReadingLabel: Text {
        let calendar = Calendar.current
        let seconds = model.visibleSessions.filter { calendar.isDateInToday($0.start) }.reduce(0) { $0 + $1.seconds }
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return Text("今日已读 \(minutes / 60) 小时 \(minutes % 60) 分钟") }
        return Text("今日已读 \(minutes) 分钟")
    }

    /// 先续读最近读过的书，再选本地书。漫画也可从首页主动续读。
    private var heroEntry: ShelfEntry? {
        model.lastReadingBook
            ?? model.visibleEntries.first { $0.local && !$0.isComic }
            ?? model.visibleEntries.first { $0.local }
    }

    /// 今日一句数据源：全部可见书目的划线按 date 取最新一条（划线存于各书 entry.highlights，时间字段为 date）。
    private var latestHighlight: Highlight? {
        model.visibleEntries.flatMap { $0.highlights ?? [] }.max { $0.date < $1.date }
    }

    private func continueStrip(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            HStack(alignment: .top, spacing: Theme.space3) {
                CoverView(title: entry.title, color: entry.color, author: entry.author,
                          image: model.covers[entry.id], width: 64, usesIndexPalette: true)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.space1) {
                    Text(entry.title).font(IndexTheme.editorial(22, relativeTo: .title2))
                        .foregroundStyle(IndexTheme.ink)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .accessibilityIdentifier("study.heroTitle")
                        .accessibilityLabel(entry.title)
                    Text(entry.author.isEmpty ? entry.format : entry.author)
                        .font(.caption).foregroundStyle(IndexTheme.muted)
                    if entry.started, entry.chapterCount > 0 {
                        let current = min(max(1, entry.progress.chapter + 1), entry.chapterCount)
                        let chapter = entry.isComic
                            ? Text("第 \(current) / \(entry.chapterCount) 页")
                            : Text("第 \(current) / \(entry.chapterCount) 章")
                        chapter.font(.caption).monospacedDigit().foregroundStyle(IndexTheme.muted)
                            .accessibilityIdentifier("study.heroChapter")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize { continueProgressLabel(entry) }
            }
            if typeSize.isAccessibilitySize { continueProgressLabel(entry) }
            if entry.started {
                ProgressBar(value: entry.readFraction, track: IndexTheme.edge,
                            tint: IndexTheme.accent, height: Theme.progressHeight)
                    .accessibilityHidden(true)
            }
            adaptiveRow {
                Button {
                    Haptics.light()
                    model.open(entry)
                } label: {
                    IndexActionLabel(title: entry.started ? "继续阅读" : "开始阅读")
                }
                .buttonStyle(IndexActionStyle(role: .primary, expands: true))
                .accessibilityIdentifier("study.heroContinue")
                Button {
                    if !entry.isComic { UserDefaults.standard.set(entry.id, forKey: "study.openFocus.bookID") }
                    Haptics.light()
                    model.open(entry)
                } label: {
                    IndexActionLabel(title: "开始专注", symbol: Icon.sleepTimer)
                }
                .buttonStyle(IndexActionStyle(role: .secondary, expands: typeSize.isAccessibilitySize))
                .accessibilityIdentifier("study.heroFocus")
            }
        }
        .padding(Theme.cardInset)
        .indexPanel(fill: IndexTheme.surface)
    }

    private func continueProgressLabel(_ entry: ShelfEntry) -> some View {
        let label = !entry.started ? Text("待读") :
            entry.readFraction >= 0.995 ? Text("已读完") : Text(entry.percentText)
        return label.font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(IndexTheme.accent).fixedSize(horizontal: false, vertical: true)
    }

    private func todayQuote(_ highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text("今日一句").font(.subheadline.weight(.semibold)).foregroundStyle(IndexTheme.accent)
                .accessibilityAddTraits(.isHeader)
            Text(highlight.text).font(IndexTheme.editorial(19, relativeTo: .title3)).foregroundStyle(IndexTheme.ink)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
            if let entry = model.visibleEntries.first(where: { ($0.highlights ?? []).contains(where: { $0.id == highlight.id }) }) {
                Text("《\(entry.title)》 · \(entry.author.isEmpty ? L("佚名") : entry.author)")
                    .font(.caption).foregroundStyle(IndexTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardInset)
        .background(IndexTheme.surface, in: RoundedRectangle(cornerRadius: IndexTheme.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IndexTheme.panelRadius, style: .continuous)
                .strokeBorder(IndexTheme.rule, lineWidth: Theme.hairline)
        }
    }

    private var addBookButton: some View {
        Button { searching = false; showingSources = true } label: {
            IndexActionLabel(title: "添书", symbol: Icon.add)
        }
        .buttonStyle(IndexActionStyle(role: heroEntry == nil ? .primary : .secondary))
        .accessibilityIdentifier("import.book")
        .accessibilityLabel("添书")
    }

    private var searchScope: Text {
        kind == "comics" ? Text("搜索所有分组中的漫画") : Text("搜索所有分组中的书籍")
    }

    private var searchEntry: some View {
        Button(action: startSearch) {
            IndexActionLabel(title: "搜索", symbol: Icon.search)
        }
        .buttonStyle(IndexActionStyle())
        .accessibilityLabel(searchScope)
        .accessibilityIdentifier("shelf.search")
    }

    private var kindSelector: some View {
        HStack(spacing: Theme.space2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.space1) {
                    kindButton("书籍", value: "books")
                    kindButton("漫画", value: "comics")
                    Button { showingGroups.toggle() } label: {
                        kindLabel("分组", selected: showingGroups)
                    }
                    .buttonStyle(PressButtonStyle())
                    .accessibilityAddTraits(showingGroups ? .isSelected : [])
                }
            }
            libraryOptions
        }
    }

    private func kindLabel(_ title: LocalizedStringKey, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? IndexTheme.accent : IndexTheme.muted)
            .padding(.horizontal, Theme.space3)
            .frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
            .background(selected ? IndexTheme.surface : .clear, in: Capsule())
            .contentShape(Rectangle())
    }

    private func kindButton(_ title: LocalizedStringKey, value: String) -> some View {
        let selected = kind == value && !showingGroups
        let count = model.visibleEntries.filter { value == "comics" ? $0.isComic : !$0.isComic }.count
        return Button {
            Haptics.selection()
            withAnimation(IndexTheme.transition) {
                kind = value
                category = nil
                showingGroups = false
            }
        } label: {
            kindLabel(title, selected: selected)
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(count) 本"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var shelfControls: some View {
        if editing {
            let displayed = Set(sorted.map(\.id))
            let allSelected = !displayed.isEmpty && selection == displayed
            adaptiveRow {
                Text("已选择 \(selection.count) 本")
                    .font(IndexTheme.editorial(22, relativeTo: .title2)).foregroundStyle(IndexTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button {
                    selection = allSelected ? [] : displayed
                } label: {
                    IndexActionLabel(title: allSelected ? "取消全选" : "全选")
                }
                .buttonStyle(IndexActionStyle(role: .secondary))
                .disabled(displayed.isEmpty).accessibilityIdentifier("shelf.selectAll")
            }
        } else {
            if !searching { viewOptions }
            collectionCount
                .font(.caption).foregroundStyle(IndexTheme.muted)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var collectionCount: some View {
        HStack(spacing: Theme.space2) {
            if !folders.isEmpty { Text("\(folders.count) 个分组") }
            if !sorted.isEmpty || folders.isEmpty { Text("\(sorted.count) 本书") }
        }
        .accessibilityElement(children: .combine)
    }

    private var scopeNotice: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            if editing {
                Text(isRoot
                     ? "可跨分组选择。选好后用下方操作整理；新建分组在「移动分组」中。"
                     : "选择本分组的书籍后，在下方移动、隐藏或删除。")
                    .font(.caption).foregroundStyle(IndexTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !searchText.isEmpty && !searching {
                Text("搜索结果：\(searchText)")
                    .font(.caption).foregroundStyle(IndexTheme.muted)
            }
            if hasFilters {
                adaptiveRow {
                    Text([filter == "全部" ? nil : L(filter), category].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.weight(.medium)).foregroundStyle(IndexTheme.accent)
                    Button("清除筛选") { filter = "全部"; category = nil }
                        .buttonStyle(IndexActionStyle())
                        .accessibilityIdentifier("shelf.clearFilters")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 筛选、排序、视图与批量整理分别保留自己的操作入口。
    private var viewOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.space1) { collectionActions }
                .fixedSize(horizontal: true, vertical: false)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)], spacing: 0) {
                collectionActions
            }
        }
    }

    @ViewBuilder private var collectionActions: some View {
        filterMenu
        sortMenu
        layoutMenu
        organizeButton
    }

    private var organizeButton: some View {
        Button("整理", action: beginEditing)
            .buttonStyle(IndexActionStyle())
            .disabled(visibleKindEntries.isEmpty)
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
                .foregroundStyle(hasFilters ? IndexTheme.accent : IndexTheme.muted)
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
        .foregroundStyle(IndexTheme.muted)
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
        .foregroundStyle(IndexTheme.muted)
        .accessibilityLabel("显示方式：\(useList ? L("列表") : L("网格"))")
        .accessibilityHint(typeSize.isAccessibilitySize ? "大字号下使用列表，原有显示偏好保持不变" : "切换封面网格或书目列表")
        .accessibilityIdentifier("shelf.layout")
    }

    private func optionLabel(_ icon: String, _ title: LocalizedStringKey) -> some View {
        IndexActionLabel(title: title, symbol: icon)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Theme.space2)
            .frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
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
            optionLabel(Icon.more, "更多").foregroundStyle(IndexTheme.muted)
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
        VStack(alignment: .leading, spacing: Theme.space1) {
            adaptiveRow {
                HStack(spacing: Theme.space2) {
                    ThemeIcon(symbol: Icon.search, size: 17)
                        .foregroundStyle(IndexTheme.muted).accessibilityHidden(true)
                    TextField("书名、作者、分类或分组", text: $query)
                        .font(.body).foregroundStyle(IndexTheme.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onSubmit { rememberSearch(); searchFocused = false }
                        .accessibilityLabel(searchScope)
                        .accessibilityIdentifier("shelf.search-field")
                    if !query.isEmpty {
                        Button { query = ""; searchFocused = true } label: {
                            ThemeIcon(symbol: Icon.clearText)
                        }
                        .buttonStyle(IndexActionStyle())
                        .accessibilityLabel("清除搜索文字")
                    }
                }
                .padding(.leading, Theme.space3)
                .padding(.trailing, query.isEmpty ? Theme.space3 : 0)
                .frame(minHeight: IndexTheme.actionHeight)
                .background(IndexTheme.surface, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: IndexTheme.controlRadius)
                        .strokeBorder(searchFocused ? IndexTheme.accent : IndexTheme.edge,
                                      lineWidth: searchFocused ? Theme.ruleMedium : Theme.rule)
                        .allowsHitTesting(false)
                }
                Button("取消", action: cancelSearch).buttonStyle(IndexActionStyle())
            }
            searchScope.font(.caption).foregroundStyle(IndexTheme.muted)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(IndexTheme.accent)
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
        VStack(alignment: .leading, spacing: Theme.space1) {
            if !savedSearches.isEmpty {
                HStack {
                    Text("最近搜索").font(.subheadline.weight(.semibold)).foregroundStyle(IndexTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Theme.space2)
                    Button("清空") { savedSearches = "" }.buttonStyle(IndexActionStyle())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.space2) {
                        ForEach(savedSearches.split(separator: "\n").map(String.init), id: \.self) { term in
                            Button(term) { query = term; searchFocused = false }
                                .buttonStyle(IndexActionStyle(role: .secondary))
                        }
                    }
                }
            }
            if searchText.isEmpty {
                Text("搜索覆盖所有分组。隐藏书籍需验证后查看。")
                    .font(.caption).foregroundStyle(IndexTheme.muted)
            }
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
        if !searchText.isEmpty || hasFilters {
            collectionNotice("没有符合条件的书", detail: "换个关键词，或调整筛选。")
        } else if kind == "comics" && isRoot && visibleKindEntries.isEmpty {
            collectionNotice("还没有漫画", detail: "导入 CBZ 或图片 ZIP 压缩包，会在这里以漫画模式阅读。",
                             addTitle: "导入漫画")
        } else if model.entries.isEmpty {
            collectionNotice("从第一本书开始", detail: "支持 EPUB、TXT、PDF、MOBI、AZW3、CBZ 与听页备份，也可使用 WiFi 传书、WebDAV 或 OPDS。",
                             addTitle: "导入书籍")
        } else if isRoot && showingGroups && !editing {
            collectionNotice("还没有分组", detail: "在书库选择「整理」，再通过「移动分组」创建。")
        } else if editing {
            collectionNotice("没有可选择的书籍", detail: "退出整理后可以调整筛选或导入书籍。")
        } else if isRoot {
            collectionNotice("没有符合条件的书", detail: "换个关键词，或调整筛选。")
        } else {
            collectionNotice("这个分组是空的", detail: "回到书库点右上角「整理」，选择书籍后通过「移动分组」移入这里。")
        }
    }

    private func collectionNotice(_ title: LocalizedStringKey, detail: LocalizedStringKey,
                                  addTitle: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text(title).font(IndexTheme.editorial(22, relativeTo: .title2))
                .foregroundStyle(IndexTheme.ink).accessibilityAddTraits(.isHeader)
            Text(detail).font(.subheadline).foregroundStyle(IndexTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let addTitle {
                Button { showingSources = true } label: {
                    IndexActionLabel(title: addTitle, symbol: Icon.add)
                }
                .buttonStyle(IndexActionStyle(role: .secondary))
            }
        }
        .padding(Theme.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .indexPanel()
    }

    // MARK: 网格（书阁陈列）

    private var bookGrid: some View {
        let columns = [GridItem(.adaptive(minimum: widthClass == .regular ? 152 : 116),
                                spacing: Theme.space3, alignment: .top)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.space4) {
            ForEach(folders, id: \.self) { path in
                VStack(alignment: .leading, spacing: 0) {
                    NavigationLink { ShelfView(group: path) } label: { folderTile(path) }
                        .buttonStyle(PressButtonStyle())
                        .contextMenu { folderMenu(path) }
                    folderActions(path)
                }
            }
            ForEach(sorted) { entry in
                bookCell(entry) { gridTile(entry) }
            }
        }
        .padding(Theme.space3)
        .indexPanel()
    }

    @ViewBuilder
    private func bookCell<Content: View>(_ entry: ShelfEntry, @ViewBuilder label: () -> Content) -> some View {
        if editing {
            let selected = selection.contains(entry.id)
            Button { toggle(entry.id) } label: {
                HStack(spacing: Theme.space2) {
                    ThemeIcon(symbol: Icon.selection(selected), size: 20)
                        .foregroundStyle(selected ? IndexTheme.accent : IndexTheme.muted)
                        .accessibilityHidden(true)
                    label()
                }
                .padding(.horizontal, Theme.space2)
                .background(selected ? IndexTheme.wash : .clear,
                            in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityLabel(selected ? Text("取消选择《\(entry.title)》") : Text("选择《\(entry.title)》"))
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else if useList || searching {
            adaptiveRow {
                readingButton(entry, label: label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                detailLink(entry).padding(.leading, Theme.space1)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                readingButton(entry, label: label)
                IndexRule().padding(.top, Theme.space1)
                detailLink(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                Text("详情").font(.caption.weight(.medium)).foregroundStyle(IndexTheme.accent)
                ThemeIcon(symbol: Icon.disclosure, size: 11).foregroundStyle(IndexTheme.muted)
                    .accessibilityHidden(true)
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
                                CoverView(title: book.title, color: book.color,
                                          image: model.covers[book.id], width: w, usesIndexPalette: true)
                        }
                    }
                    .padding(Theme.space3)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .indexPanel(fill: IndexTheme.wash)
            .padding(.bottom, Theme.space3)
            HStack(spacing: Theme.space1) {
                ThemeIcon(symbol: Icon.folder, size: 12)
                    .foregroundStyle(IndexTheme.accent)
                Text(String(path.split(separator: "/").last ?? ""))
                    .font(IndexTheme.editorial(17, relativeTo: .body))
                    .foregroundStyle(IndexTheme.ink)
                    .lineLimit(1)
            }
            .padding(.top, Theme.space2)
            Text("\(books.count) 本书")
                .font(.caption)
                .foregroundStyle(IndexTheme.muted)
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
            optionLabel(Icon.moreCircle, "管理").foregroundStyle(IndexTheme.accent)
        }
        .accessibilityLabel("管理分组 \(path)")
    }

    private func gridTile(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FlexibleCover(title: entry.title, color: entry.color, author: entry.author,
                          image: model.covers[entry.id], usesIndexPalette: true)
                .overlay(alignment: .topLeading) {
                    if entry.isHidden {
                        SealBadge(text: "已隐藏", color: IndexTheme.ink, background: IndexTheme.surface)
                            .padding(Theme.space2)
                            .accessibilityLabel("已隐藏")
                    }
                }
            Text(entry.title)
                .font(IndexTheme.editorial(17, relativeTo: .body))
                .foregroundStyle(IndexTheme.ink)
                .lineLimit(2)
                .padding(.top, Theme.space2)
            authorLabel(entry).font(.caption).foregroundStyle(IndexTheme.muted).lineLimit(1)
                .padding(.top, Theme.space1)
            positionLabel(entry).font(.caption.monospacedDigit()).foregroundStyle(IndexTheme.accent)
            if let lastRead = lastReadLabel(entry) {
                Text(lastRead)
                    .font(.caption2).foregroundStyle(IndexTheme.muted)
                    .lineLimit(1).padding(.top, Theme.space1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func authorLabel(_ entry: ShelfEntry) -> Text {
        entry.author.isEmpty ? Text("佚名") : Text(entry.author)
    }

    private func positionLabel(_ entry: ShelfEntry) -> Text {
        guard entry.local else { return Text("iCloud 藏书") }
        if !entry.started { return Text("待读") }
        if entry.readFraction >= 0.995 { return Text("已读完 · \(entry.percentText)") }
        let current = min(max(1, entry.progress.chapter + 1), max(1, entry.chapterCount))
        return entry.isComic
            ? Text("第 \(current) 页 · \(entry.percentText)")
            : Text("第 \(current) 章 · \(entry.percentText)")
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

    // MARK: 列表

    private var bookList: some View {
        let entries = sorted
        let lastID = entries.last?.id
        return LazyVStack(spacing: 0) {
            ForEach(folders, id: \.self) { path in
                HStack(spacing: Theme.space2) {
                    NavigationLink { ShelfView(group: path) } label: {
                        HStack(spacing: Theme.space3) {
                            ThemeIcon(symbol: Icon.folderFill, size: 20)
                                .foregroundStyle(IndexTheme.accent)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Theme.space1) {
                                Text(String(path.split(separator: "/").last ?? ""))
                                    .font(IndexTheme.editorial(17, relativeTo: .body))
                                    .foregroundStyle(IndexTheme.ink)
                                Text("\(booksInCurrentKind(path).count) 本书")
                                    .font(.caption).foregroundStyle(IndexTheme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: Theme.rowMinHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle())
                    .contextMenu { folderMenu(path) }
                    folderActions(path)
                }
                IndexRule()
            }
            ForEach(entries) { entry in
                bookCell(entry) { bookRow(entry) }
                if entry.id != lastID { IndexRule() }
            }
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, Theme.space1)
        .indexPanel()
    }

    private func bookRow(_ entry: ShelfEntry) -> some View {
        HStack(spacing: Theme.space3) {
            CoverView(title: entry.title, color: entry.color, author: entry.author,
                      image: model.covers[entry.id], width: 40, usesIndexPalette: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(entry.title).font(IndexTheme.editorial(17, relativeTo: .body))
                    .foregroundStyle(IndexTheme.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                authorLabel(entry).font(.caption).foregroundStyle(IndexTheme.muted)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                if editing {
                    let selected = selection.contains(entry.id)
                    Text(selected ? "已选择" : "未选择")
                        .font(.caption).foregroundStyle(selected ? IndexTheme.accent : IndexTheme.muted)
                } else {
                    positionLabel(entry).font(.caption.monospacedDigit())
                        .foregroundStyle(IndexTheme.accent)
                    if !searching, let lastRead = lastReadLabel(entry) {
                        Text(lastRead).font(.caption2).foregroundStyle(IndexTheme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.space2)
        .frame(minHeight: Theme.rowMinHeight)
        .contentShape(Rectangle())
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
            if !selection.isEmpty && removableSelection.isEmpty {
                Text("示例书籍可分组或隐藏")
                    .font(.caption)
                    .foregroundStyle(IndexTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .indexPanel()
        .padding(.horizontal, Theme.space4)
        .padding(.bottom, Theme.space2)
        .frame(maxWidth: Theme.pageWidth)
        .frame(maxWidth: .infinity)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func editButton(_ title: String, _ icon: String, destructive: Bool = false, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.space1) {
                ThemeIcon(symbol: icon, size: 18).accessibilityHidden(true)
                Text(L(title)).font(.caption.weight(.medium)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(destructive ? IndexTheme.danger : IndexTheme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight)
            .background(destructive ? IndexTheme.dangerWash : IndexTheme.wash,
                        in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
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
                IndexHeading(title: Text("移动分组"), detail: Text("已选择 \(count) 本"), large: true)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section {
                    VStack(alignment: .leading, spacing: Theme.space2) {
                        Text("分组名称").font(.subheadline.weight(.semibold)).foregroundStyle(IndexTheme.ink)
                            .accessibilityHidden(true)
                        TextField("分组名称，可用 / 创建多级分组", text: $name)
                            .accessibilityLabel("分组名称，可用 / 创建多级分组")
                            .submitLabel(.done).onSubmit(create)
                            .padding(.horizontal, Theme.space3).frame(minHeight: Theme.rowMinHeight)
                            .background(IndexTheme.canvas, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: IndexTheme.controlRadius)
                                    .strokeBorder(IndexTheme.edge, lineWidth: Theme.rule).allowsHitTesting(false)
                            }
                        Button(action: create) {
                            IndexActionLabel(title: model.groupPaths.contains(targetPath) ? "移入这个分组" : "新建并移入",
                                             symbol: Icon.folderAdd)
                        }
                        .buttonStyle(IndexActionStyle(role: .primary))
                        .disabled(targetPath.isEmpty || count == 0)
                    }
                    .padding(.vertical, Theme.space2)
                } header: {
                    Text("新建分组")
                } footer: {
                    if let parentGroup { Text("在「\(parentGroup)」内创建，并移入已选的 \(count) 本书。") }
                    else { Text("创建后立即移入已选的 \(count) 本书。取消不会创建空分组。") }
                }
                .listRowBackground(IndexTheme.surface)
                Section("移动到已有位置") {
                    Button { pick(nil) } label: {
                        IndexRowLabel(title: Text("书库首页 · 不分组"), symbol: Icon.unfiled)
                    }
                    ForEach(model.groupPaths, id: \.self) { path in
                        Button { pick(path) } label: {
                            IndexRowLabel(title: Text(verbatim: path), symbol: Icon.folder)
                        }
                    }
                }
                .buttonStyle(PressButtonStyle())
                .listRowBackground(IndexTheme.surface)
            }
            .indexList()
            .scrollDismissesKeyboard(.interactively)
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
extension ImportReport {
    var indexSummary: Text {
        if !finished { return Text("已处理 \(completed) / \(items.count) 个文件") }
        if failures == 0 { return Text("已导入 \(successes) 个文件") }
        return Text("\(successes) 个成功 · \(failures) 个失败")
    }
}

struct ImportResultsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        IndexPage {
            HStack(alignment: .top, spacing: Theme.space2) {
                IndexHeading(title: Text("导入结果"), large: true)
                Button { dismiss() } label: { ThemeIcon(symbol: Icon.close) }
                    .buttonStyle(IndexActionStyle())
                    .accessibilityLabel("关闭导入结果")
            }
            if let report = model.importReport {
                reportSummary(report)
                LazyVStack(spacing: 0) {
                    ForEach(report.items) { item in
                        resultRow(item)
                        if item.id != report.items.last?.id { IndexRule() }
                    }
                }
                .padding(.horizontal, Theme.space3)
                .indexPanel()
            } else {
                IndexStatus(kind: .empty, title: Text("暂无导入记录"),
                            detail: Text("导入书籍后，可以在这里查看每个文件的状态。"))
                Button("选择文件") { model.requestFileImport(); dismiss() }
                    .buttonStyle(IndexActionStyle(role: .primary))
                    .disabled(model.busy)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let report = model.importReport, report.finished { reportActions(report) }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func reportSummary(_ report: ImportReport) -> some View {
        if report.finished {
            let title: LocalizedStringKey = report.successes == 0 ? "这批文件未能导入"
                : report.failures == 0 ? "成功的书籍已加入书库" : "部分文件需要处理"
            IndexStatus(kind: report.failures == 0 ? .success : .failure, title: Text(title),
                        detail: report.indexSummary)
            if report.failures > 0 {
                Text("请查看逐项原因，再重新选择需要处理的文件。成功项会保留。")
                    .font(.subheadline).foregroundStyle(IndexTheme.muted)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.space2) {
                IndexHeading(title: Text("正在导入书籍"))
                ProgressView(value: Double(report.completed), total: Double(max(1, report.items.count))) {
                    report.indexSummary
                        .font(.subheadline).foregroundStyle(IndexTheme.muted)
                }
                .tint(IndexTheme.accent)
            }
            .padding(Theme.space4)
            .indexPanel(fill: IndexTheme.wash)
        }
    }

    private func reportActions(_ report: ImportReport) -> some View {
        VStack(spacing: 0) {
            IndexRule()
            VStack(spacing: Theme.space1) {
                Button { model.requestFileImport(); dismiss() } label: {
                    IndexActionLabel(title: report.failures > 0 ? "重新选择失败文件" : "继续导入文件")
                }
                .buttonStyle(IndexActionStyle(role: report.failures > 0 ? .primary : .secondary, expands: true))
                .disabled(model.busy).accessibilityIdentifier("import.retrySelection")
                Button("前往书库") { model.tab = 0; dismiss() }
                    .buttonStyle(IndexActionStyle(role: report.failures > 0 ? .plain : .primary, expands: true))
            }
            .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space2)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .background(IndexTheme.canvas)
    }

    private func resultRow(_ item: ImportItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space3) {
            resultIcon(item).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(verbatim: item.name).font(.body.weight(.medium)).foregroundStyle(IndexTheme.ink)
                resultDescription(item)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.space3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func resultIcon(_ item: ImportItem) -> some View {
        switch item.state {
        case .waiting: ThemeIcon(symbol: Icon.duration).foregroundStyle(IndexTheme.muted)
        case .importing: ProgressView().tint(IndexTheme.accent)
        case .imported: ThemeIcon(symbol: Icon.markRead).foregroundStyle(IndexTheme.accent)
        case .failed: ThemeIcon(symbol: Icon.warning).foregroundStyle(IndexTheme.danger)
        }
    }

    @ViewBuilder private func resultDescription(_ item: ImportItem) -> some View {
        switch item.state {
        case .waiting: Text("等待导入").font(.caption).foregroundStyle(IndexTheme.muted)
        case .importing: Text("正在解析并保存").font(.caption).foregroundStyle(IndexTheme.accent)
        case .imported: Text("已加入书库").font(.caption).foregroundStyle(IndexTheme.accent)
        case .failed(let reason):
            Text("导入失败").font(.caption.weight(.semibold)).foregroundStyle(IndexTheme.danger)
            Text(L(reason)).font(.subheadline).foregroundStyle(IndexTheme.muted)
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
