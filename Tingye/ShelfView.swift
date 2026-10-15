import SwiftUI
import UniformTypeIdentifiers

/// 刊版书架：只管找书与整理。页头「书架」+ 整理 / 信号红「＋」，3pt 刊头线，描边搜索框，下划线分段，色块封面网格。
struct ShelfView: View {
    /// 当前所在分组；nil 为书库根目录
    var group: String? = nil
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var filter = "全部"
    @State private var category: String?
    @State private var importing = false
    @State private var showingSources = false
    @State private var searching = false
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
    @AppStorage("shelf.layout") private var layout = "grid"
    @AppStorage("shelf.kind") private var kind = "books"
    #if DEBUG
    @State private var reviewDetail: String?
    #endif

    private var isRoot: Bool { group == nil }
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
        return visibleKindEntries.filter { isRoot ? ($0.group ?? "").isEmpty : $0.group == group }
    }
    private var categories: [String] { Set(visibleKindEntries.map { model.category($0) }).sorted() }
    private var filtered: [ShelfEntry] { pool.filter { entry in
        (searchText.isEmpty || (entry.title + entry.author + model.category(entry) + (entry.group ?? "")).localizedCaseInsensitiveContains(searchText)) &&
        (filter == "全部" || (filter == "在读" ? entry.started : !entry.started)) &&
        (category == nil || model.category(entry) == category)
    } }
    private var sorted: [ShelfEntry] {
        switch model.sortOrder {
        case "title": filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case "author": filtered.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
        case "added": filtered.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }
        default: filtered.sorted { $0.progress.updatedAt > $1.progress.updatedAt }
        }
    }
    private var folders: [String] {
        guard !editing, searchText.isEmpty, !hasFilters else { return [] }
        return model.subgroups(of: group).filter { path in model.books(inGroup: path).contains { kind == "comics" ? $0.isComic : !$0.isComic } }
    }
    private var sortLabel: String {
        ["title": "书名", "author": "作者", "added": "添加时间"][model.sortOrder] ?? "最近阅读"
    }
    private var totalTime: String {
        let minutes = Int(model.readingSeconds.values.reduce(0, +) / 60)
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }
    private var title: String { group.map { String($0.split(separator: "/").last ?? "") } ?? "书架" }

    var body: some View {
        observedShelf
        #if DEBUG
        .navigationDestination(item: $reviewDetail) { id in BookDetailView(entryID: id) }
        .task {
            if ["shelf", "shelf-list", "shelf-edit"].contains(UIReview.screen) { kind = "books" }
            if ["shelf", "shelf-edit"].contains(UIReview.screen) { layout = "grid" }
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
                if isRoot { shelfHeader }
                if isRoot { InkRule(height: Theme.ruleHeavy).padding(.top, 14) }
                if !editing {
                    if searching { shelfSearchBar.padding(.top, 18) }
                    else { searchEntry.padding(.top, isRoot ? 18 : 0) }
                }
                if isRoot && !editing {
                    kindSelector.padding(.top, 14)
                } else {
                    shelfControls.padding(.top, 16)
                }
                if editing || !searchText.isEmpty || hasFilters {
                    if isRoot && !editing { shelfControls.padding(.top, 8) }
                    scopeNotice.padding(.top, 8)
                }
                if sorted.isEmpty && folders.isEmpty {
                    emptyState
                } else {
                    if layout == "list" { bookList.padding(.top, 12) } else { bookGrid.padding(.top, 8) }
                }
                if isRoot {
                    Text("EPUB · TXT · PDF · MOBI · AZW3 · CBZ · 听页备份")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                }
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, isRoot ? 12 : 4)
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
        .preference(key: LibraryNavigationHiddenKey.self, value: editing)
        .animation(Theme.smoothSpring, value: editing)
        .bookImporter(isPresented: $importing)
        .sheet(isPresented: $showingSources) { ImportHubView().environmentObject(model).tint(Theme.accent) }
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
        .onChange(of: model.tab) { _, tab in if tab != 1 { finishEditing(); searching = false } }
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
        let noun = kind == "comics" ? "漫画" : "书"
        return "\(visibleKindEntries.count) 本\(noun) · 累计 \(totalTime)"
    }

    private var shelfHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            PageMasthead(title: "书架", subtitle: shelfSubtitle)
            if !editing {
                CircleIconButton(systemName: Icon.organize, label: "整理书库", action: beginEditing)
                    .disabled(visibleKindEntries.isEmpty)
                    .accessibilityIdentifier("shelf.organize")
                addBooksMenu
            }
        }
    }

    private var addBooksMenu: some View {
        Menu {
            Button { importing = true } label: { Label("从文件导入", systemImage: Icon.importFile) }
            Button { searching = false; showingSources = true } label: { Label("更多导入方式", systemImage: Icon.discover) }
        } label: {
            ThemeIcon(symbol: Icon.add, size: 22, weight: .bold)
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("import.book")
        .accessibilityLabel("添加书籍")
    }

    private var searchEntry: some View {
        Button(action: startSearch) {
            HStack(spacing: 8) {
                ThemeIcon(symbol: Icon.search, size: 22)
                    .foregroundStyle(Theme.ink3)
                Text(searchText.isEmpty ? "书名、作者、分类" : searchText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索所有分组中的\(kind == "comics" ? "漫画" : "书籍")")
        .accessibilityIdentifier("shelf.search")
    }

    private var kindSelector: some View {
        HStack(alignment: .bottom, spacing: 22) {
            kindButton("书籍", value: "books")
            kindButton("漫画", value: "comics")
            Spacer(minLength: 8)
            viewOptions.padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kindButton(_ title: String, value: String) -> some View {
        let selected = kind == value
        let count = model.visibleEntries.filter { value == "comics" ? $0.isComic : !$0.isComic }.count
        return Button {
            Haptics.selection()
            withAnimation(Theme.pressSpring) { kind = value; category = nil }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(title)
                    Text("\(count)").monospacedDigit()
                }
                .font(.system(size: selected ? 20 : 16, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Theme.ink : Theme.ink3)
                Rectangle().fill(Theme.accent).frame(height: 3).opacity(selected ? 1 : 0)
            }
            .fixedSize()
            .frame(minHeight: 44, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 本")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var shelfControls: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(editing ? "选择要整理的书" : (!searchText.isEmpty ? "搜索结果" : (hasFilters ? "筛选结果" : (model.sortOrder == "added" ? "最近加入" : "全部藏书"))))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if editing || hasFilters || !searchText.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 12)
            if editing {
                Button(selection == Set(sorted.map(\.id)) && !sorted.isEmpty ? "取消全选" : "全选") {
                    selection = selection == Set(sorted.map(\.id)) ? [] : Set(sorted.map(\.id))
                }
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(sorted.isEmpty)
            } else {
                viewOptions
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
            if !searchText.isEmpty {
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
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var viewOptions: some View {
        Menu {
            Picker("阅读状态", selection: $filter) {
                Text("全部状态").tag("全部")
                Text("在读").tag("在读")
                Text("未读").tag("未开卷")
            }
            Picker("分类", selection: $category) {
                Text("全部分类").tag(String?.none)
                ForEach(categories, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Picker("排序", selection: $model.sortOrder) {
                Label("最近阅读", systemImage: Icon.sortRecent).tag("recent")
                Label("书名", systemImage: Icon.sortTitle).tag("title")
                Label("作者", systemImage: Icon.sortAuthor).tag("author")
                Label("添加时间", systemImage: Icon.sortAdded).tag("added")
            }
            Picker("显示方式", selection: $layout) {
                Label("封面网格", systemImage: Icon.grid).tag("grid")
                Label("书目列表", systemImage: Icon.list).tag("list")
            }
            Divider()
            if hasFilters { Button("清除筛选") { filter = "全部"; category = nil } }
            if model.hiddenUnlocked {
                Button { model.hiddenUnlocked = false } label: { Label("收起隐藏书籍", systemImage: Icon.visibilityAction(currentlyVisible: true)) }
            } else {
                Button { Task { await model.unlockHidden() } } label: { Label("显示隐藏书籍", systemImage: Icon.visibilityAction(currentlyVisible: false)) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(sortLabel)
                Image(systemName: Icon.disclosure).font(.system(size: 11, weight: .bold))
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("查看选项，筛选、排序和显示方式")
        .accessibilityIdentifier("shelf.view-options")
    }

    // MARK: 主入口：添加、搜索、整理

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if editing {
            ToolbarItem(placement: .topBarTrailing) {
                Button("取消整理", action: finishEditing)
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
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
            }
        }
    }

    private var shelfSearchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        .onSubmit { searchFocused = false }
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
                .frame(minHeight: 46)
                .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.5))
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

    private func startSearch() {
        searching = true
        searchFocused = true
    }

    private func cancelSearch() {
        searchFocused = false
        searching = false
        query = ""
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
                Text("导入一本喜欢的书，让这里成为你的私人书房。也可在「＋」导入面板中使用 WiFi 传书、WebDAV 或 OPDS。")
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 152), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
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
    }

    @ViewBuilder
    private func bookCell<Content: View>(_ entry: ShelfEntry, @ViewBuilder label: () -> Content) -> some View {
        if editing {
            Button { toggle(entry.id) } label: {
                label().overlay(alignment: .topTrailing) {
                    Image(systemName: Icon.selection(selection.contains(entry.id)))
                        .font(.system(size: 22))
                        .foregroundStyle(selection.contains(entry.id) ? Theme.accent : .white)
                        .background(Circle().fill(selection.contains(entry.id) ? .white : .black.opacity(0.35)))
                        .padding(6)
                }
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityLabel("\(selection.contains(entry.id) ? "取消选择" : "选择")《\(entry.title)》")
            .accessibilityAddTraits(selection.contains(entry.id) ? .isSelected : [])
        } else if layout == "list" {
            HStack(spacing: 0) {
                readingButton(entry, label: label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                detailLink(entry).padding(.trailing, 10)
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
            searching = false
            model.open(entry)
        } label: { label() }
        .buttonStyle(PressButtonStyle())
        .accessibilityIdentifier("book." + entry.id)
        .accessibilityLabel("\(entry.started ? "继续阅读" : "开始阅读")《\(entry.title)》")
        .accessibilityHint("书籍信息与管理请使用旁边的详情按钮")
        .contextMenu { menu(entry) }
    }

    private func detailLink(_ entry: ShelfEntry) -> some View {
        NavigationLink { BookDetailView(entryID: entry.id) } label: {
            HStack(spacing: 6) {
                if layout != "list" {
                    Text(entry.local ? (entry.started ? entry.percentText : "未读") : "iCloud")
                        .font(Theme.kicker).tracking(1)
                        .monospacedDigit()
                        .foregroundStyle(entry.started && entry.local ? Theme.accent : Theme.ink3)
                    Spacer(minLength: 0)
                }
                Image(systemName: Icon.info).font(.system(size: layout == "list" ? 17 : 13)).foregroundStyle(Theme.ink3)
            }
            .frame(minWidth: 36, minHeight: 36)
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
            Color.clear.aspectRatio(0.7, contentMode: .fit).overlay {
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
            .glassCard(cornerRadius: 12)
            .padding(.bottom, 10)
            HStack(spacing: 5) {
                Image(systemName: Icon.folderFill)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
                Text(String(path.split(separator: "/").last ?? ""))
                    .font(Theme.serifSemibold(14, relativeTo: .subheadline))
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

    private func gridTile(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FlexibleCover(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id])
                .overlay(alignment: .topLeading) {
                    if entry.isHidden {
                        Image(systemName: Icon.hiddenBadge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(6)
                            .accessibilityLabel("已隐藏")
                    }
                }
            Text(entry.title)
                .font(Theme.serifSemibold(14, relativeTo: .subheadline))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
                                .foregroundStyle(Theme.accent)
                                .frame(width: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(path.split(separator: "/").last ?? ""))
                                    .font(Theme.serifSemibold(16, relativeTo: .body))
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
                        BookCoverView(title: row.title, color: row.color, author: row.author, image: model.covers[row.id], width: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(Theme.serifSemibold(16, relativeTo: .body))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(row.author + " · " + model.category(row))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.ink3)
                                .lineLimit(1)
                            if row.started && row.local {
                                ProgressBar(value: row.readFraction, height: 3)
                                    .frame(maxWidth: 120)
                                    .padding(.top, 3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.local ? (row.started ? row.percentText : "未读") : "iCloud")
                            .font(row.started ? Theme.display(22) : .system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(row.started ? Theme.accent : Theme.ink3)
                    }
                    .padding(.trailing, editing ? 28 : 0)
                    .padding(.vertical, 12)
                    .frame(minHeight: 88)
                    .contentShape(Rectangle())
                }
                RowDivider()
            }
        }
        .overlay(alignment: .top) { InkRule() }
    }

    @ViewBuilder
    private func menu(_ entry: ShelfEntry) -> some View {
        Button { model.open(entry) } label: {
            Label(entry.started ? "继续阅读" : "开始阅读", systemImage: Icon.read)
        }
        if !entry.isComic {
            Button { model.listen(entry.id) } label: {
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
                }
                editButton(allSelectedHidden ? "取消隐藏" : "隐藏", Icon.visibilityAction(currentlyVisible: !allSelectedHidden), disabled: selection.isEmpty, action: hideSelectedBooks)
                editButton("删除", Icon.delete, destructive: true, disabled: removableSelection.isEmpty) {
                    removalSelection = removableSelection
                    removing = true
                }
            }
        }
        .padding(12)
        .floatingPanel(cornerRadius: 22)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func editButton(_ title: String, _ icon: String, destructive: Bool = false, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(destructive ? Theme.danger : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).strokeBorder(destructive ? Theme.danger : Theme.ink, lineWidth: 1.2))
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
                model.message = "已隐藏 \(ids.count) 本书。可在书库的排序菜单或「设置」中验证身份后显示。"
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

private struct BookImportModifier: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                model.run("正在导入书籍") {
                    try await model.importFiles(urls)
                    model.message = "已导入 \(urls.count) 个文件。"
                }
            case .failure(let error):
                model.message = error.localizedDescription
            }
        }
    }
}

extension View {
    func bookImporter(isPresented: Binding<Bool>) -> some View { modifier(BookImportModifier(isPresented: isPresented)) }
}

struct ExportedBook: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
