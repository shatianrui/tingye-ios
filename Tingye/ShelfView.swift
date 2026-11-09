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
    @State private var importing = false
    @State private var showingSources = false
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
    private var adaptiveRow: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10)) }
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
                if !editing {
                    if searching { shelfSearchBar }
                    else { searchEntry.padding(.top, isRoot ? 18 : 0) }
                }
                if isRoot && !editing && !searching { kindSelector.padding(.top, 14) }
                shelfControls.padding(.top, editing ? 16 : 8)
                if editing || !searchText.isEmpty || hasFilters { scopeNotice.padding(.top, 8) }
                if sorted.isEmpty && folders.isEmpty {
                    emptyState
                } else {
                    if useList || editing || searching { bookList.padding(.top, 12) } else { bookGrid.padding(.top, 8) }
                }
                if searching { recentSearches.padding(.top, 20) }
                if !editing && !searching {
                    Button { showingSources = true } label: { Label("添加书籍", systemImage: Icon.add) }
                        .buttonStyle(SecondaryButtonStyle(height: 50)).padding(.top, 20)
                        .accessibilityIdentifier("import.book")
                }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, isRoot ? 10 : 4)
            .padding(.bottom, 32)
            .frame(maxWidth: 820).frame(maxWidth: .infinity)
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
        .bookImporter(isPresented: $importing)
        .sheet(isPresented: $showingSources) { ImportHubView().environmentObject(model).tint(Theme.accent) }
        .sheet(isPresented: $showingImportResults) { NavigationStack { ImportResultsView() }.environmentObject(model).tint(Theme.accent) }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("私人藏书 · 随时翻阅").font(.caption).foregroundStyle(Theme.ink2)
                    Text(title).font(Theme.serifBold(34, relativeTo: .largeTitle))
                        .foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                }
                Spacer()
                CircleIconButton(systemName: Icon.search, label: "搜索书库", action: startSearch)
            }
            Text(shelfSubtitle).font(.caption).foregroundStyle(Theme.ink2)
        }
    }

    private var addBooksMenu: some View {
        Menu {
            Button { importing = true } label: { Label("从文件导入", systemImage: Icon.importFile) }
            Button { searching = false; showingSources = true } label: { Label("更多导入方式", systemImage: Icon.discover) }
            if model.importReport != nil {
                Button { showingImportResults = true } label: { Label("最近导入结果", systemImage: Icon.list) }
            }
        } label: {
            Label("添加", systemImage: Icon.add)
                .font(.subheadline.weight(.bold)).foregroundStyle(Theme.onClay)
                .padding(.horizontal, 14).frame(minWidth: 44, minHeight: 44)
                .background(Theme.clay, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("import.book")
        .accessibilityLabel("添加书籍")
    }

    private var searchEntry: some View {
        Button(action: startSearch) {
            HStack(spacing: 9) {
                ThemeIcon(symbol: Icon.search, size: 21)
                    .foregroundStyle(Theme.ink3)
                Text(searchText.isEmpty ? "搜索书名、作者或分组" : searchText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索所有分组中的\(kind == "comics" ? "漫画" : "书籍")")
        .accessibilityIdentifier("shelf.search")
    }

    private var kindSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                kindButton("书籍", value: "books")
                kindButton("漫画", value: "comics")
                Button { showingGroups.toggle() } label: {
                    Text("分组").font(.caption).padding(.horizontal, 16).frame(minHeight: 40)
                        .foregroundStyle(showingGroups ? Theme.onAccent : Theme.ink2)
                        .background(showingGroups ? Theme.accent : Theme.surface2, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(showingGroups ? .isSelected : [])
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
            Text(L(title)).font(.caption).padding(.horizontal, 16).frame(minHeight: 40)
                .foregroundStyle(selected ? Theme.onAccent : Theme.ink2)
                .background(selected ? Theme.accent : Theme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 本")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var shelfControls: some View {
        if editing {
            adaptiveRow {
                VStack(alignment: .leading, spacing: 5) {
                    Text("已选择 \(selection.count) 本书").font(.headline).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    Text(summary).font(.caption).foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: 8)
                Button(selection == Set(sorted.map(\.id)) && !sorted.isEmpty ? "取消全选" : "全选") {
                    selection = selection == Set(sorted.map(\.id)) ? [] : Set(sorted.map(\.id))
                }
                .font(.subheadline.weight(.medium)).frame(minWidth: 44, minHeight: 44)
                .disabled(sorted.isEmpty).accessibilityIdentifier("shelf.selectAll")
            }
        } else {
            viewOptions
            if hasFilters || !searchText.isEmpty {
                Text("\(!searchText.isEmpty ? "搜索结果" : "筛选结果") · \(summary)")
                    .font(.caption).foregroundStyle(Theme.ink3).padding(.top, 4)
            }
        }
    }

    private var scopeNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editing {
                Text(isRoot ? "可跨分组选择。选好后用下方操作整理；新建分组在「移动分组」中。" : "选择本分组的书籍后，在下方移动、隐藏或删除。")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
            if !searchText.isEmpty && !searching {
                Label(kind == "comics" ? "正在搜索所有分组中的漫画" : "正在搜索所有分组中的书籍", systemImage: Icon.search)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }
            if hasFilters {
                HStack(spacing: 8) {
                    Text([filter == "全部" ? nil : filter, category].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Button("清除筛选") { filter = "全部"; category = nil }
                        .font(.caption.weight(.medium))
                        .frame(minHeight: 44)
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
            HStack(spacing: 2) {
                Text(searching ? "找到 \(sorted.count) 本书" : "全部 \(sorted.count)").font(.caption).foregroundStyle(Theme.ink2)
                Spacer(minLength: 4)
                if !searching { filterMenu; sortMenu; layoutMenu; organizeButton }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(summary).font(.caption).foregroundStyle(Theme.ink2)
                HStack(spacing: 8) { filterMenu; sortMenu; layoutMenu; organizeButton }
            }
        }
    }

    private var organizeButton: some View {
        Button("整理", action: beginEditing).font(.caption).foregroundStyle(Theme.accent)
            .frame(minWidth: 44, minHeight: 44).disabled(visibleKindEntries.isEmpty)
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
                Label("最近阅读", systemImage: Icon.sortRecent).tag("recent")
                Label("书名", systemImage: Icon.sortTitle).tag("title")
                Label("作者", systemImage: Icon.sortAuthor).tag("author")
                Label("添加时间", systemImage: Icon.sortAdded).tag("added")
                Label("手动排序", systemImage: Icon.list).tag("manual")
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
                    Label("封面网格", systemImage: Icon.grid).tag("grid")
                    Label("书目列表", systemImage: Icon.list).tag("list")
                }
            }
        } label: { optionLabel(useList ? Icon.list : Icon.grid, "视图") }
        .foregroundStyle(Theme.ink2)
        .accessibilityLabel("显示方式：\(useList ? "列表" : "网格")")
        .accessibilityHint(typeSize.isAccessibilitySize ? "大字号下使用列表，原有显示偏好保持不变" : "切换封面网格或书目列表")
        .accessibilityIdentifier("shelf.layout")
    }

    private func optionLabel(_ icon: String, _ text: String) -> some View {
        Text(L(text)).font(.caption).foregroundStyle(Theme.accent)
            .padding(.horizontal, 4).frame(minWidth: 40, minHeight: 44).contentShape(Rectangle())
    }

    private var libraryOptions: some View {
        Menu {
            if model.hiddenUnlocked {
                Button { model.hiddenUnlocked = false } label: { Label("收起隐藏书籍", systemImage: Icon.visibilityAction(currentlyVisible: true)) }
            } else {
                Button { Task { await model.unlockHidden() } } label: { Label("显示隐藏书籍", systemImage: Icon.visibilityAction(currentlyVisible: false)) }
            }
        } label: {
            Label("更多", systemImage: Icon.more).font(.caption)
                .foregroundStyle(Theme.ink2).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
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
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("shelf.finishOrganizing")
            }
        } else if !isRoot {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { importing = true } label: { Label("从文件导入", systemImage: Icon.importFile) }
                    Button { searching = false; showingSources = true } label: { Label("更多导入方式", systemImage: Icon.discover) }
                } label: {
                    Text("添加").font(.subheadline.weight(.medium)).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("import.book")
                .accessibilityLabel("添加书籍")
                // 搜索框已常驻在正文顶部，导航栏只保留添加与整理
                Button(action: beginEditing) {
                    Text("整理").font(.subheadline.weight(.medium)).frame(minWidth: 44, minHeight: 44)
                }
                .disabled(visibleKindEntries.isEmpty)
                .accessibilityIdentifier("shelf.organize")
                libraryOptions
            }
        }
    }

    private var shelfSearchBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("搜索书库").font(Theme.sans(28, weight: .bold)).foregroundStyle(Theme.ink)
            Text("按书名、作者或分组搜索").font(.caption).foregroundStyle(Theme.ink2)
            HStack(spacing: 8) {
                HStack(spacing: 8) {
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
                            Image(systemName: Icon.clearText)
                                .foregroundStyle(Theme.ink3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索文字")
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, query.isEmpty ? 14 : 0)
                .frame(minHeight: 48)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("取消", action: cancelSearch)
                    .font(.subheadline)
                    .frame(minWidth: 44, minHeight: 44)
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
        VStack(alignment: .leading, spacing: 12) {
            if !savedSearches.isEmpty {
                HStack {
                    Text("最近搜索").font(Theme.sans(20, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button("清空") { savedSearches = "" }.font(.caption).frame(minHeight: 44)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(savedSearches.split(separator: "\n").map(String.init), id: \.self) { term in
                            Button { query = term; searchFocused = false } label: {
                                Text(term).font(.caption).foregroundStyle(Theme.ink2).padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Theme.surface2, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("搜索覆盖所有分组。隐藏书籍需验证后查看。")
                .font(.caption).foregroundStyle(Theme.ink2).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            ContentUnavailableView.search(text: searchText).padding(.vertical, 40)
        } else if kind == "comics" && isRoot && visibleKindEntries.isEmpty {
            ContentUnavailableView {
                Label("还没有漫画", systemImage: Icon.comics)
            } description: {
                Text("导入 CBZ 或图片 ZIP 压缩包，会在这里以漫画模式阅读。")
            } actions: {
                Button("导入漫画") { importing = true }.buttonStyle(PrimaryButtonStyle(height: 44)).frame(width: 160)
            }
            .padding(.vertical, 40)
        } else if model.entries.isEmpty {
            ContentUnavailableView {
                Label("从第一本书开始", systemImage: Icon.shelf)
            } description: {
                Text("支持 EPUB、TXT、PDF、MOBI、AZW3、CBZ 与听页备份。在「添加」中也可使用 WiFi 传书、WebDAV 或 OPDS。")
            } actions: {
                Button("导入书籍") { importing = true }
                    .buttonStyle(PrimaryButtonStyle(height: 44))
                    .frame(width: 160)
            }
            .padding(.vertical, 40)
        } else {
            ContentUnavailableView {
                Label(isRoot ? "没有符合条件的书" : "这个分组是空的", systemImage: isRoot ? Icon.search : Icon.folder)
            } description: {
                Text(isRoot ? "换个关键词，或调整筛选。" : "回到书库点右上角「整理」，选择书籍后通过「移动分组」移入这里。")
            }
            .padding(.vertical, 40)
        }
    }

    // MARK: 网格（书阁陈列）

    private var bookGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
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
                HStack(spacing: 14) {
                    Image(systemName: Icon.selection(selection.contains(entry.id)))
                        .font(.system(size: 22)).foregroundStyle(selection.contains(entry.id) ? Theme.accent : Theme.ink3)
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
                detailLink(entry).padding(.leading, 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                readingButton(entry, label: label)
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
            HStack(spacing: 6) {
                if !useList {
                    Text(entry.local ? (entry.started ? entry.percentText : "待读") : "iCloud")
                        .font(Theme.kicker).tracking(1)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                    Spacer(minLength: 0)
                }
                Text("详情").font(.caption).foregroundStyle(Theme.accent)
                Image(systemName: Icon.disclosure).font(.caption2).foregroundStyle(Theme.ink3)
            }
            .frame(minWidth: 44, minHeight: 44)
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
                    let w = (geo.size.width - 30) / 2
                    LazyVGrid(columns: [GridItem(.fixed(w), spacing: 8), GridItem(.fixed(w), spacing: 8)], spacing: 8) {
                        ForEach(books.prefix(4)) { book in
                            BookCoverView(title: book.title, color: book.color, image: model.covers[book.id], width: w)
                        }
                    }
                    .padding(11)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .glassCard()
            .padding(.bottom, 10)
            HStack(spacing: 5) {
                Image(systemName: Icon.folderFill)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
                Text(String(path.split(separator: "/").last ?? ""))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .padding(.top, 6)
            Text("\(books.count) 本书")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.ink3)
                .padding(.top, 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("分组 \(path)，\(books.count) 本")
    }

    @ViewBuilder
    private func folderMenu(_ path: String) -> some View {
        Button { renameText = String(path.split(separator: "/").last ?? ""); renaming = path } label: { Label("重命名", systemImage: Icon.edit) }
        Button(role: .destructive) { dissolvingGroup = path } label: { Label("删除分组（保留书籍）", systemImage: Icon.folderRemove) }
    }

    private func folderActions(_ path: String) -> some View {
        Menu { folderMenu(path) } label: {
            Label("管理", systemImage: Icon.moreCircle)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.ink2)
                .frame(minWidth: 52, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("管理分组 \(path)")
    }

    private func gridTile(_ entry: ShelfEntry, index: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FlexibleCover(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], index: index)
                .overlay(alignment: .topLeading) {
                    if entry.isHidden {
                        Image(systemName: Icon.hiddenBadge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.6), in: Rectangle())
                            .padding(6)
                            .accessibilityLabel("已隐藏")
                    }
                }
            Text(entry.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.top, 8)
            if let lastRead = lastReadLabel(entry) {
                Text(lastRead)
                    .font(.caption2).foregroundStyle(Theme.ink2)
                    .lineLimit(1).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
                        HStack(spacing: 14) {
                            Image(systemName: Icon.folderFill)
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(path.split(separator: "/").last ?? ""))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                Text("\(booksInCurrentKind(path).count) 本书")
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink3)
                            }
                            Spacer(minLength: 8)
                        }
                        .frame(minHeight: 76)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.99))
                    .contextMenu { folderMenu(path) }
                    folderActions(path).padding(.trailing, 10)
                }
                RowDivider()
            }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                bookCell(row) {
                    HStack(spacing: 14) {
                        BookCoverView(title: row.title, color: row.color, author: row.author, image: model.covers[row.id], width: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Text((row.author.isEmpty ? "佚名" : row.author) + " · " + row.format)
                                .font(.caption)
                                .foregroundStyle(Theme.ink3)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            Text(editing ? (selection.contains(row.id) ? "已选择" : "未选择") : readingSummary(row))
                                .font(.caption).foregroundStyle(Theme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                            if !editing, let lastRead = lastReadLabel(row) {
                                Text(lastRead)
                                    .font(.caption2).foregroundStyle(Theme.ink2)
                                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.trailing, 0)
                    .padding(.vertical, 12)
                    .frame(minHeight: 96)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func menu(_ entry: ShelfEntry) -> some View {
        Button { model.open(entry) } label: {
            Label(entry.started ? "继续阅读" : "开始阅读", systemImage: Icon.read)
        }
        if model.sortOrder == "manual" {
            Section("手动排序") {
                Button { ManualShelfOrder.move(entry.id, in: sorted, kind: kind, by: -1); model.objectWillChange.send() } label: { Label("前移一位", systemImage: "arrow.up") }
                Button { ManualShelfOrder.move(entry.id, in: sorted, kind: kind, by: 1); model.objectWillChange.send() } label: { Label("后移一位", systemImage: "arrow.down") }
                Button { ManualShelfOrder.move(entry.id, in: sorted, kind: kind, to: 0); model.objectWillChange.send() } label: { Label("移到最前", systemImage: "arrow.up.to.line") }
                Button { ManualShelfOrder.move(entry.id, in: sorted, kind: kind, to: .max); model.objectWillChange.send() } label: { Label("移到最后", systemImage: "arrow.down.to.line") }
            }
        }
        if !entry.isComic {
            Button {
                if model.player.book?.id == entry.id { model.showingPlayer = true }
                else { model.listen(entry.id) }
            } label: {
                Label(model.player.book?.id == entry.id ? "打开播放器" : "听书", systemImage: Icon.listen)
            }
        }
        Divider()
        Button { moveSelection = [entry.id]; moving = true } label: { Label("移动分组 / 新建分组", systemImage: Icon.folder) }
        Button { model.setHidden([entry.id], !entry.isHidden) } label: {
            Label(entry.isHidden ? "取消隐藏" : "隐藏", systemImage: Icon.visibilityAction(currentlyVisible: !entry.isHidden))
        }
    }

    // MARK: 多选操作

    private var editBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("已选择 \(selection.count) 本")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer()
                if !selection.isEmpty && removableSelection.isEmpty {
                    Text("示例书籍可分组或隐藏")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink3)
                }
            }
            .padding(.horizontal, 12)
            HStack(spacing: 6) {
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
        .padding(12)
        .floatingPanel(cornerRadius: Theme.radius)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func editButton(_ title: String, _ icon: String, destructive: Bool = false, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 18))
                Text(L(title)).font(.caption.weight(.medium)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(destructive ? Theme.danger : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(destructive ? Theme.danger.opacity(0.09) : Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
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
                Section {
                    TextField("分组名称，可用 / 创建多级分组", text: $name)
                        .submitLabel(.done)
                        .onSubmit(create)
                        .frame(minHeight: 44)
                    Button(action: create) {
                        Label(model.groupPaths.contains(targetPath) ? "移入这个分组" : "新建并移入", systemImage: Icon.folderAdd)
                            .frame(minHeight: 44)
                    }
                    .disabled(targetPath.isEmpty || count == 0)
                } header: { Text("新建分组") } footer: {
                    Text(parentGroup.map { "在「\($0)」内创建，并移入已选的 \(count) 本书。" } ?? "创建后立即移入已选的 \(count) 本书。取消不会创建空分组。")
                }
                .listRowBackground(Theme.surface)
                Section("移动到已有位置") {
                    Button { pick(nil) } label: {
                        Label("书库首页 · 不分组", systemImage: Icon.unfiled)
                            .frame(minHeight: 44)
                    }
                    ForEach(model.groupPaths, id: \.self) { path in
                        Button { pick(path) } label: {
                            Label(path, systemImage: Icon.folder)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("移动 \(count) 本书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.frame(minHeight: 44)
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

/// Copy selected provider documents into the sandbox before parsing them.
/// The ordinary entry imports one book on tap; batch selection is a separate explicit action.
struct LocalBookPicker: UIViewControllerRepresentable {
    var allowsMultipleSelection = false
    let completion: ([URL]) -> Void

    static func controller(allowsMultipleSelection: Bool, delegate: UIDocumentPickerDelegate) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = delegate
        #if DEBUG
        if UIReview.isolated && UIReview.screen == "sources-file-import" {
            picker.directoryURL = UIReview.localImportDirectory
        }
        #endif
        return picker
    }
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = Self.controller(allowsMultipleSelection: allowsMultipleSelection, delegate: context.coordinator)
        picker.view.accessibilityIdentifier = "bookImport.documentPicker"
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var completed = false
        private let completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }
        private func finish(_ urls: [URL]) {
            guard !completed else { return }
            completed = true
            completion(urls)
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish([]) }
    }
}

private struct BookImportModifier: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool
    var allowsMultipleSelection = false
    @State private var pickedURLs: [URL] = []
    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            let urls = pickedURLs
            pickedURLs = []
            // Begin only after the picker is gone, so results can be presented immediately.
            if !urls.isEmpty { model.beginImport(urls) }
        }) {
            LocalBookPicker(allowsMultipleSelection: allowsMultipleSelection) { urls in
                pickedURLs = urls
                isPresented = false
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func bookImporter(isPresented: Binding<Bool>, allowsMultipleSelection: Bool = false) -> some View {
        modifier(BookImportModifier(isPresented: isPresented, allowsMultipleSelection: allowsMultipleSelection))
    }
}

/// 最近一批导入的逐项结果。失败文件重新选择，避免复用已经失效的安全作用域 URL。
struct ImportResultsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("导入结果").font(Theme.sans(28, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    CircleIconButton(systemName: Icon.close, label: "关闭导入结果") { dismiss() }
                }
                Text("成功的书籍已加入书库。").font(.caption).foregroundStyle(Theme.ink2).padding(.bottom, 4)
                if let report = model.importReport {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(report.finished ? (report.failures > 0 ? "\(report.successes) 本成功，\(report.failures) 本需要处理" : "\(report.successes) 本书导入成功") : "正在导入书籍")
                            .font(Theme.sans(20, weight: .bold)).foregroundStyle(Theme.ink)
                        Text("全部 \(report.items.count) 个文件 · " + (report.finished ? "本次导入已完成" : "已处理 \(report.completed) 个"))
                            .font(.caption).foregroundStyle(Theme.ink2)
                        if !report.finished { ProgressView(value: Double(report.completed), total: Double(max(1, report.items.count))).tint(Theme.accent) }
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    LazyVStack(spacing: 10) {
                        ForEach(report.items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                resultIcon(item)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                                    resultDescription(item)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if report.finished {
                        Button(report.failures > 0 ? "重新选择失败文件" : "继续导入文件") { importing = true }
                            .buttonStyle(SecondaryButtonStyle(height: 50)).disabled(model.busy)
                        Button("前往书库") { model.tab = 0; dismiss() }.buttonStyle(PrimaryButtonStyle(height: 50))
                        Text(report.failures > 0 ? "成功与失败逐项显示；已成功的文件会保留。请检查原因后重新选择失败文件。" : "文件已保存到本机书库，可以开始阅读了。")
                            .font(.caption).foregroundStyle(Theme.ink2).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    ContentUnavailableView("暂无导入记录", systemImage: Icon.importFile, description: Text("导入书籍后，可以在这里查看每个文件的状态。"))
                    Button("选择文件") { importing = true }.buttonStyle(PrimaryButtonStyle(height: 50))
                }
            }
            .padding(.horizontal, Theme.inset).padding(.top, 10).padding(.bottom, 24)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .paperBackground().toolbar(.hidden, for: .navigationBar)
        .bookImporter(isPresented: $importing)
    }
    @ViewBuilder private func resultIcon(_ item: ImportItem) -> some View {
        switch item.state {
        case .waiting: Image(systemName: Icon.duration).foregroundStyle(Theme.ink2)
        case .importing: ProgressView().tint(Theme.accent)
        case .imported: Image(systemName: "checkmark.circle").foregroundStyle(Theme.jade)
        case .failed: Image(systemName: Icon.close).foregroundStyle(Theme.danger)
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
