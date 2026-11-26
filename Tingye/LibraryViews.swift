import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - 书籍详情

/// 纸面上的书封、清晰的书籍信息与阅读进度。
struct BookDetailView: View {
    let entryID: String
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var repair = false
    @State private var removal = false
    @State private var export: ExportedBook?
    @State private var intro: String?
    @State private var showingIntro = false
    @State private var chapterBook: Book?
    @State private var chapterTitles: [String] = []
    @State private var loadingPreview = true
    @State private var moving = false
    var entry: ShelfEntry? { model.entries.first { $0.id == entryID } }

    var body: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: Theme.space5) {
                    HStack(spacing: Theme.space2) {
                        CircleIconButton(systemName: Icon.back, label: "返回书库") { dismiss() }
                        Text(entry.group.map { "收于「\($0)」" } ?? "私人书库")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.ink3)
                        Spacer()
                    }

                    hero(entry)
                    readingStats(entry)
                    actionButtons(entry)
                    contentSection(entry)
                    briefSection(entry)
                    PaperCard(padding: Theme.space4) {
                        VStack(alignment: .leading, spacing: 0) {
                            Button { moving = true } label: {
                                detailRow(icon: Icon.folder, title: "分组", subtitle: entry.group ?? "未分组")
                            }.buttonStyle(.plain)
                            manageSection(entry)
                        }
                    }
                }
                .padding(.horizontal, Theme.inset)
                .padding(.top, Theme.space3)
                .padding(.bottom, Theme.space7)
                .frame(maxWidth: Theme.pageWidth)
                .frame(maxWidth: .infinity)
            } else {
                EmptyState(title: "这本书已不在书架上", detail: "")
                    .padding(.top, Theme.space7)
            }
        }
        .paperBackground()
        .navigationTitle("书籍详情")
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: true)
        .task(id: entry?.local) { await loadReadingDetails() }
        .navigationDestination(item: $chapterBook) { book in ChapterManagerView(book: book) }
        .fileImporter(isPresented: $repair, allowedContentTypes: [.data]) { result in switch result { case .success(let url): model.run("正在修复原书") { try await model.repair(entryID, from: url) }; case .failure(let error): model.message = error.localizedDescription } }
        .confirmationDialog("移除《\(entry?.title ?? "")》?", isPresented: $removal, titleVisibility: .visible) {
            Button("仅删除本机", role: .destructive) { do { try model.removeLocal(entryID); dismiss() } catch { model.message = error.localizedDescription } }
            Button("删除本机和 iCloud", role: .destructive) { model.removeLocalAndICloud(entryID); dismiss() }
        } message: { Text("「仅删除本机」保留 iCloud 备份，之后可还原；「删除本机和 iCloud」会从所有 iCloud 备份快照与进度同步中移除这本书，无法恢复。") }
        .sheet(item: $export) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $moving) {
            GroupPickerView(count: 1) { path in model.move([entryID], toGroup: path) }
                .environmentObject(model).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingIntro) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        Masthead(title: "关于这本书", subtitle: entry?.title, titleSize: 28)
                        if let entry { PaperCard { introSection(entry) } }
                    }.padding(Theme.inset)
                }
                .background(Theme.bg)
                .navigationTitle("关于这本书")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showingIntro = false } } }
            }
        }
        #if DEBUG
        .task {
            if UIReview.screen == "chapters", chapterBook == nil { chapterBook = try? model.book(entryID) }
        }
        #endif
    }

    // MARK: 书籍信息

    /// 封面宽 104pt 是既有书封排版尺寸；大字号时改为纵排，仍保留封面。
    private func hero(_ entry: ShelfEntry) -> some View {
        (typeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space4))
         : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.space5))) {
            CoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 104)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.space3) {
                Text(entry.title).font(Theme.serif(28, relativeTo: .title)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(entry.author.isEmpty ? "佚名" : entry.author) · \(entry.format) · \(max(1, entry.chapterCount)) \(chapterUnit(entry))")
                    .font(Theme.sans(13)).monospacedDigit().foregroundStyle(Theme.ink3)
                Text(entry.local ? (entry.started ? (entry.readFraction >= 0.995 ? "已读完" : "阅读中 · " + entry.percentText) : "待读") : "iCloud 藏书")
                    .font(Theme.sans(13)).monospacedDigit().foregroundStyle(Theme.clayDeep)
                if entry.local && entry.started {
                    Text("读至第 \(entry.progress.chapter + 1) \(chapterUnit(entry))")
                        .font(Theme.sans(13)).monospacedDigit().foregroundStyle(Theme.ink3)
                        .accessibilityIdentifier("detail.readingProgress")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 逐书累计时长使用既有会话记录；不把按日总时长误当作该书时长。
    private func readingStats(_ entry: ShelfEntry) -> some View {
        let seconds = model.visibleSessions.filter { $0.bookID == entry.id }.reduce(0) { $0 + $1.seconds }
        let minutes = Int(seconds / 60)
        let duration = minutes >= 60 ? "\(minutes / 60)小时\(minutes % 60)分" : "\(minutes)分"
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.space5) {
                StatBlock(value: entry.percentText, label: "进度").frame(maxWidth: .infinity, alignment: .leading)
                StatBlock(value: duration, label: "累计时长").frame(maxWidth: .infinity, alignment: .leading)
                StatBlock(value: "\(entry.notes.count)", label: "摘记数").frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: Theme.space5) {
                StatBlock(value: entry.percentText, label: "进度")
                StatBlock(value: duration, label: "累计时长")
                StatBlock(value: "\(entry.notes.count)", label: "摘记数")
            }
        }
        .padding(.vertical, Theme.space4)
        .overlay(alignment: .top) { RowDivider() }
        .overlay(alignment: .bottom) { RowDivider() }
    }

    private func chapterUnit(_ entry: ShelfEntry) -> String {
        entry.isComic || entry.format.uppercased() == "PDF" ? "页" : "章"
    }

    @ViewBuilder
    private func actionButtons(_ entry: ShelfEntry) -> some View {
        if !entry.local {
            NavigationLink { ICloudBackupView() } label: { Text("从备份恢复书籍") }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            VStack(spacing: Theme.space3) {
                ClayButton("打开") { Haptics.light(); model.open(entry) }
                .accessibilityIdentifier("detail.reading")
                if !entry.isComic {
                    Button { Haptics.light(); model.listen(entryID) } label: {
                        Label { Text(model.player.book?.id == entryID && model.player.playing ? "打开听书" : "听这本书") } icon: { ThemeIcon(symbol: Icon.listen) }
                            .font(Theme.sans(15, weight: .medium)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: Theme.iconButtonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("detail.listen")
                    .accessibilityHint("辅助朗读，保留当前阅读位置")
                }
            }
        }
    }

    private func briefSection(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            SectionHeader(title: "关于这本书")
            PaperCard {
                Button { showingIntro = true } label: {
                    VStack(alignment: .leading, spacing: Theme.space2) {
                        Text(intro ?? (entry.local ? "这本书未提供简介。" : "还原到本机后可查看简介与目录。"))
                            .font(.subheadline)
                            .lineSpacing(6)
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        if intro != nil { Text("阅读全文").font(.footnote.weight(.medium)).foregroundStyle(Theme.clayDeep) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(intro == nil)
            }
        }
    }

    private func introSection(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.space4) {
            Text(intro ?? (entry.local ? "这本书未提供简介。" : "还原到本机后可查看简介与目录。"))
                .font(.body)
                .lineSpacing(7)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.space1)
    }

    @ViewBuilder private func contentSection(_ entry: ShelfEntry) -> some View {
        if entry.local {
            VStack(alignment: .leading, spacing: Theme.space3) {
                SectionHeader(title: "目录与书摘")
                Button {
                    Task {
                        do { chapterBook = try await model.loadBook(entryID) }
                        catch { model.message = error.localizedDescription }
                    }
                } label: {
                    detailRow(icon: Icon.contents, title: "全部目录", subtitle: "\(entry.chapterCount) \(chapterUnit(entry))")
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityIdentifier("detail.contents")
                if !chapterTitles.isEmpty {
                    VStack(spacing: 0) {
                        let start = min(max(0, entry.progress.chapter), chapterTitles.count - 1)
                        ForEach(start..<min(start + 3, chapterTitles.count), id: \.self) { index in
                            Button {
                                let position = index == entry.progress.chapter ? entry.progress.position : 0
                                model.open(entry, chapter: index, position: position)
                            } label: {
                                HairlineRow {
                                    HStack(alignment: .center, spacing: Theme.space3) {
                                        Text(String(format: "%02d", index + 1))
                                            .font(.caption).monospacedDigit()
                                            .foregroundStyle(entry.started && index == entry.progress.chapter ? Theme.clayDeep : Theme.ink3)
                                        VStack(alignment: .leading, spacing: Theme.space1) {
                                            Text(chapterTitles[index]).font(Theme.serif(17))
                                            .foregroundStyle(entry.started && index == entry.progress.chapter ? Theme.clayDeep : Theme.ink).multilineTextAlignment(.leading)
                                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                            if entry.started && index == entry.progress.chapter {
                                                SealDot(text: "读到这里")
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, Theme.space3)
                                    .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("detail.chapter.\(index)")
                            .accessibilityLabel("\(entry.started && index == entry.progress.chapter ? "继续阅读" : "阅读")，\(chapterTitles[index])")
                        }
                    }
                } else if loadingPreview {
                    Text("正在载入目录预览…").font(.caption).foregroundStyle(Theme.ink2)
                }
                NavigationLink {
                    List { EditorialIntro(title: "书摘与笔记", detail: "保留原文，也留住当时的想法。")
                        NotesList(entryID: entryID) { note in model.open(entry, target: .init(note)) } }
                        .editorialList()
                        .background(Theme.bg)
                        .navigationTitle("书摘与笔记")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.visible, for: .navigationBar)
                        .toolbar(.hidden, for: .tabBar)
                        .preference(key: LibraryNavigationHiddenKey.self, value: true)
                } label: {
                    detailRow(icon: Icon.highlight, title: "书摘与笔记", subtitle: "\(entry.notes.count) 条")
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityIdentifier("detail.notes")
                NavigationLink {
                    List {
                        EditorialIntro(title: "阅读书签", detail: "从留下的位置继续读。")
                        if entry.bookmarks.isEmpty {
                            ContentUnavailableView("还没有书签", systemImage: Icon.bookmark(false), description: Text("阅读时点按顶部书签，留下想回来的位置。"))
                                .listRowBackground(Color.clear)
                        }
                        ForEach(entry.bookmarks.sorted { $0.date > $1.date }) { bookmark in
                            Button { model.open(entry, target: .init(bookmark)) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("第 \(bookmark.chapter + 1) \(chapterUnit(entry))").font(.caption).foregroundStyle(Theme.accent)
                                    Text(bookmark.excerpt.isEmpty ? "回到这个阅读位置" : bookmark.excerpt)
                                        .font(.body).foregroundStyle(Theme.ink).lineLimit(3)
                                }
                                .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain).listRowBackground(Theme.surface)
                        }
                    }
                    .editorialList().background(Theme.bg)
                    .navigationTitle("阅读书签").navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .tabBar)
                    .preference(key: LibraryNavigationHiddenKey.self, value: true)
                } label: {
                    detailRow(icon: Icon.bookmark(false), title: "阅读书签", subtitle: "\(entry.bookmarks.count) 个")
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityIdentifier("detail.bookmarks")
            }
        }
    }

    private func manageSection(_ entry: ShelfEntry) -> some View {
        Menu {
            Button { showingIntro = true } label: { Label { Text("查看书籍简介") } icon: { ThemeIcon(symbol: Icon.info) } }
            if entry.local {
                Button { exportBook(entry) } label: { Label { Text("导出书籍备份") } icon: { ThemeIcon(symbol: Icon.share) } }
            }
            if !entry.sample {
                if entry.local { Button { repair = true } label: { Label { Text("修复图文与封面") } icon: { ThemeIcon(symbol: Icon.repair) } } }
                if entry.local && entry.format.uppercased() == "TXT" {
                    Button { model.run("正在重新分章") { try await model.resplit(entryID) } } label: { Label { Text("按分章规则重新分章") } icon: { ThemeIcon(symbol: Icon.contents) } }
                }
                Divider()
                Button(role: .destructive) { removal = true } label: { Label { Text("移除书籍…") } icon: { ThemeIcon(symbol: Icon.delete) } }
            }
        } label: {
            HairlineRow(title: "更多操作", value: "导出 · 修复 · 移除", symbol: Icon.more, disclosure: true, showsDivider: false)
        }
        .accessibilityLabel("书籍简介、导出与管理")
    }

    private func detailRow(icon: String, title: String, subtitle: String) -> some View {
        HairlineRow(title: title, value: subtitle, symbol: icon, disclosure: true)
    }

    /// 简介先显示轻量缓存；目录标题在后台读书后提取，预览不在主线程解析整书。
    private func loadReadingDetails() async {
        guard entry?.local == true else { intro = nil; chapterTitles = []; loadingPreview = false; return }
        loadingPreview = true
        defer { loadingPreview = false }
        let cached = entry?.intro?.trimmingCharacters(in: .whitespacesAndNewlines)
        intro = cached?.isEmpty == false ? cached : nil
        guard let book = try? await model.loadBook(entryID), !Task.isCancelled else { return }
        chapterTitles = book.chapters.map(\.title)
        guard intro == nil else { return }
        // EPUB 未提供简介时可能存为空字符串，继续显示明确的空态。
        let loaded = [book.fields["description"]?.string, book.fields["intro"]?.string]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        intro = loaded
        if let loaded { model.updateEntries([entryID]) { $0.intro = loaded } }
    }
    /// 读取与整本编码都在后台进行：多图书籍的备份文件可达上百 MB。
    private func exportBook(_ row: ShelfEntry) {
        model.run("正在导出《\(row.title)》") { [model] in
            let book = try await model.loadBook(row.id)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(row.id + ".json")
            let packet = BackupPacket(book: book, progress: row.progress, epubAttachment: try model.disk?.backupAttachment(for: book))
            try await Task.detached(priority: .userInitiated) { try Integrity.encoder().encode(packet).write(to: url, options: .atomic) }.value
            export = ExportedBook(url: url)
        }
    }
}

extension Book: Hashable { func hash(into hasher: inout Hasher) { hasher.combine(id) } }

struct ChapterManagerView: View {
    let book: Book
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: Set<Int> = []
    @State private var selecting = false
    @State private var marking = false
    @State private var query = ""
    @State private var read: Set<Int> = []
    private var chapters: [Chapter] { book.chapters }
    private var visibleIndices: [Int] { chapters.indices.filter { query.isEmpty || chapters[$0].title.localizedCaseInsensitiveContains(query) } }
    private var allVisibleSelected: Bool { !visibleIndices.isEmpty && Set(visibleIndices).isSubset(of: selected) }

    var body: some View {
        List {
            Masthead(title: "目录与阅读状态", subtitle: "轻点章节阅读或听此章；选择后可批量标记已读。", titleSize: 28)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    Text(book.title).font(Theme.serif(20, relativeTo: .title2)).foregroundStyle(Theme.ink)
                    Text("共 \(chapters.count) 章 · 已读 \(read.count) 章")
                        .font(.caption).foregroundStyle(Theme.ink3)
                    Text(selecting ? "轻点章节进行选择，再在底部标记阅读状态。" : "轻点章节开始阅读，或选择「听此章」。")
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                }
                .padding(.vertical, Theme.space3)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Theme.space3, trailing: 0))
            }
            Section {
                ForEach(visibleIndices, id: \.self) { index in
                    HairlineRow { chapterRow(index: index, chapter: chapters[index]) }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                if visibleIndices.isEmpty {
                    EmptyState(title: "没有符合条件的章节", detail: "搜索章节").listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .tint(Theme.clayDeep)
        .environment(\.defaultMinListRowHeight, Theme.rowMinHeight)
        .background(Theme.bg)
        .navigationTitle(selecting ? "选择章节" : "目录")
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: true)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索章节")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "完成" : "选择") {
                    selecting.toggle()
                    if !selecting { selected.removeAll() }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                VStack(spacing: Theme.space3) {
                    HStack {
                        Text("已选 \(selected.count) 章").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        Button(allVisibleSelected ? "取消当前全选" : query.isEmpty ? "全选章节" : "全选搜索结果") {
                            if allVisibleSelected { selected.subtract(visibleIndices) } else { selected.formUnion(visibleIndices) }
                        }
                        .font(.subheadline).frame(minHeight: Theme.iconButtonSize).disabled(visibleIndices.isEmpty)
                    }
                    HStack(spacing: Theme.space3) {
                        Button { mark(true) } label: { Label { Text("标记已读") } icon: { ThemeIcon(symbol: Icon.markRead) } }
                            .buttonStyle(PrimaryButtonStyle())
                        Button { mark(false) } label: { Label { Text("标记未读") } icon: { ThemeIcon(symbol: Icon.markUnread) } }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .disabled(selected.isEmpty || marking)
                }
                .padding(Theme.cardInset)
                .floatingPanel()
                .padding(.horizontal, Theme.inset).padding(.bottom, Theme.space2)
                .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
            }
        }
        .onAppear { loadRead() }
    }

    private func chapterRow(index: Int, chapter: Chapter) -> some View {
        HStack(spacing: Theme.space3) {
            Button {
                if selecting {
                    if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                } else if let entry = model.entries.first(where: { $0.id == book.id }) {
                    model.open(entry, chapter: index, position: 0)
                }
            } label: {
                HStack(spacing: Theme.space3) {
                    if !selecting && isCurrent(index) {
                        Capsule().fill(Theme.clay).frame(width: Theme.ruleHeavy, height: Theme.space3)
                            .accessibilityHidden(true)
                    }
                    if selecting {
                        ThemeIcon(symbol: Icon.selection(selected.contains(index)))
                            .font(.system(size: 22)).foregroundStyle(selected.contains(index) ? Theme.ink : Theme.ink3)
                            .frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        Text(chapter.title).font(Theme.serif(17)).foregroundStyle(isCurrent(index) ? Theme.clayDeep : Theme.ink).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        Text((isCurrent(index) ? "读到这里 · " : "") + "\(read.contains(index) ? "已读" : "未读") · 共 \(chapter.text.count) 字")
                            .font(.caption).foregroundStyle(read.contains(index) ? Theme.accent : Theme.ink3)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selecting ? "\(selected.contains(index) ? "取消选择" : "选择")，\(chapter.title)" : "阅读，\(chapter.title)")
            if !selecting {
                Button { listen(chapter: index) } label: {
                    Label { Text("听此章") } icon: { ThemeIcon(symbol: Icon.listen) }
                        .font(.caption).foregroundStyle(Theme.ink2)
                        .padding(.horizontal, Theme.space3).frame(minHeight: Theme.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("听书，\(chapter.title)")
            }
        }
        .padding(.vertical, Theme.space1)
    }

    private func isCurrent(_ index: Int) -> Bool {
        guard let entry = model.entries.first(where: { $0.id == book.id }) else { return false }
        return entry.started && entry.progress.chapter == index
    }

    /// 正在听这本书时只跳章，不重建朗读。
    private func listen(chapter index: Int) {
        model.listen(book.id, chapter: index)
    }
    private func loadRead() { read = Set((try? model.book(book.id).fields["nativeReadChapters"]?.array?.compactMap(\.int)) ?? []) }
    private func mark(_ flag: Bool) {
        guard !selected.isEmpty, !marking else { return }
        marking = true
        let ids = selected
        Task {
            defer { marking = false }
            do { try await model.markChapters(book.id, chapters: ids, read: flag); selected = []; selecting = false; loadRead() }
            catch { model.message = error.localizedDescription }
        }
    }
}

// MARK: - 我的书房与个人设置

/// 设置目的地：己页签与「更多设置」页共用。
enum SettingsDestination: String, Hashable {
    case reading, fonts, voice, appearance, backup, notes, privacy, licenses, profile, txtRules, general, storage, menu
}

@ViewBuilder
func settingsDestinationView(_ route: SettingsDestination) -> some View {
    switch route {
    case .reading: ReadingPreferencesView()
    case .fonts: MyFontsView()
    case .voice: VoiceSettingsView()
    case .appearance: AppearanceView()
    case .backup: ICloudBackupView()
    case .notes: NotesUnifiedView()
    case .privacy: PrivacyPolicyView()
    case .licenses: FontLicenseView()
    case .profile: ProfileView()
    case .txtRules: TxtRulesView()
    case .general: GeneralSettingsView()
    case .storage: StorageView()
    case .menu: MenuSettingsView()
    }
}

struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("app.appearance") private var appearance = "system"
    @AppStorage("voice.provider") private var provider = "system"
    @AppStorage(ProgressSync.enabledKey) private var syncProgress = true
    @AppStorage("privacy.appLock") private var appLock = false
    @State private var export: ExportedBook?
    @State private var clearingCache = false
    @State private var settingsRoute: SettingsDestination?
    #if DEBUG
    @State private var reviewRoute: String?
    #endif
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
    private var providerName: String { VoiceOptions.providerName(provider) }
    private var appearanceName: String { ["system": "跟随系统", "light": "日间", "dark": "夜间"][appearance] ?? "跟随系统" }
    var body: some View {
        settingsList
            .navigationTitle("隐私与关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .navigationDestination(item: $settingsRoute) { route in
                settingsDestinationView(route)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
            }
            .sheet(item: $export) { ShareSheet(items: [$0.url]) }
            .confirmationDialog("清除缓存？", isPresented: $clearingCache, titleVisibility: .visible) {
                Button("清除封面、语音缓存与临时文件", role: .destructive) { clearCache() }
                Button("取消", role: .cancel) { }
            } message: { Text("已导入的书籍、书摘与阅读进度会保留。封面和语音在下次使用时重新生成。") }
            #if DEBUG
            .navigationDestination(item: $reviewRoute) { route in
                Group {
                    if route == "appearance" { AppearanceView() } else { ICloudBackupView() }
                }
                .toolbar(.visible, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
            }
            .task {
                if let screen = UIReview.screen, ["appearance", "backup"].contains(screen), reviewRoute == nil {
                    reviewRoute = screen
                }
            }
            #endif
    }

    private var settingsList: some View {
        SettingsPage(title: "隐私与关于", detail: "更细致的控制，放在这里。") {
            SettingsGroup(title: "隐私与保护", footer: "隐藏的书只在验证身份后显示，退出 App 后自动重新隐藏。") {
                HairlineRow {
                    Toggle(isOn: $appLock) {
                        EditorialRow(title: "应用锁", detail: "打开时使用\(PrivacyLock.biometryName)验证", symbol: Icon.lock(appLock), disclosure: false)
                    }.tint(Theme.clay)
                }
                Button {
                    if model.hiddenUnlocked { model.hiddenUnlocked = false } else { Task { await model.unlockHidden() } }
                } label: {
                    HairlineRow(title: model.hiddenUnlocked ? "重新隐藏私密书籍" : "查看隐藏的书",
                                value: "\(model.entries.filter(\.isHidden).count) 本",
                                symbol: Icon.visibilityAction(currentlyVisible: model.hiddenUnlocked))
                }
                settingsLink(.privacy, icon: Icon.privacy, title: "隐私政策")
            }
            SettingsGroup(title: "关于听页", footer: "\(model.entries.count) 本书，保存在本机和你的私人 iCloud。无需注册账号。") {
                HairlineRow {
                    HStack {
                        Text("版本").font(Theme.sans(16))
                        Spacer()
                        Text(version + " (" + build + ")").font(Theme.sans(13)).monospacedDigit().foregroundStyle(Theme.ink3)
                    }
                }
                settingsLink(.licenses, icon: Icon.license, title: "开源组件与字体许可")
            }
            SettingsGroup(title: "数据导出") {
                HairlineRow(showsDivider: false) { TextButton("导出阅读数据", action: exportStats) }
            }
        }
    }

    private func settingsLink(_ route: SettingsDestination, icon: String, title: String) -> some View {
        Button { settingsRoute = route } label: {
            HairlineRow {
                HStack(spacing: Theme.space3) {
                    ThemeIcon(symbol: icon, size: 20).foregroundStyle(Theme.ink2)
                    Text(L(title)).font(Theme.sans(16)).foregroundStyle(Theme.clayDeep)
                    Spacer()
                    ThemeIcon(symbol: Icon.disclosure, size: 13).foregroundStyle(Theme.ink4)
                }
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func settingsDestination(_ route: SettingsDestination) -> some View {
        settingsDestinationView(route)
    }

    private func exportStats() {
        do {
            model.flushPendingSaves()
            let payload = ReadingStatsExport(exportedAt: Date(), readingSeconds: model.readingSeconds, entries: model.entries.map { .init(id: $0.id, title: $0.title, author: $0.author, chapterCount: $0.chapterCount, percent: $0.percentText, progress: $0.progress) }, sessions: model.sessions)
            let encoder = Integrity.encoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tingye-reading-stats.json")
            try encoder.encode(payload).write(to: url, options: .atomic)
            export = ExportedBook(url: url)
        } catch { model.message = error.localizedDescription }
    }

    private func clearCache() {
        let temp = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? [] { try? FileManager.default.removeItem(at: url) }
        CloudSpeech.clearDiskCache()
        model.clearIndexCache(); model.notify("已清除封面、语音缓存与临时文件。")
    }
}

// MARK: - 外观 / 关于

/// 外观选择页:跟随系统、日间、夜间。WindowAppearance 在 TingyeApp 中读取同一键并应用。
struct AppearanceView: View {
    @AppStorage("app.appearance") private var appearance = "system"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                Masthead(title: "让听页，更合你的习惯。", subtitle: "象牙暖纸、深暖炭墨与克制陶土。选择适合此刻的界面。", kicker: "外观主题", titleSize: 28)
                VStack(spacing: Theme.space3) {
                    appearanceOption("system", title: "跟随系统", subtitle: "随设备外观自动切换")
                    appearanceOption("light", title: "日间", subtitle: "象牙暖纸、深炭文字与柔和陶土")
                    appearanceOption("dark", title: "夜间", subtitle: "深暖炭底，在夜里安静阅读")
                }
                Text("正文的纸色可在「阅读排版」中单独选择。")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, Theme.space1)
            }
            .padding(.horizontal, Theme.inset)
            .padding(.vertical, Theme.space5)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appearanceOption(_ value: String, title: String, subtitle: String) -> some View {
        let selected = appearance == value
        return Button {
            Haptics.selection()
            withAnimation(Theme.pressSpring) { appearance = value }
        } label: {
            PaperCard {
                HairlineRow(showsDivider: false) {
                    HStack(spacing: Theme.space4) {
                        appearancePreview(value)
                        VStack(alignment: .leading, spacing: Theme.space2) {
                            Text(L(title))
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text(L(subtitle))
                                .font(.caption)
                                .foregroundStyle(Theme.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ThemeIcon(symbol: Icon.selection(selected), size: 22)
                            .foregroundStyle(selected ? Theme.ink : Theme.line)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(PressButtonStyle(scale: 0.99))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("appearance.\(value)")
    }

    private func appearancePreview(_ value: String) -> some View {
        let dark = value == "dark"
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: Theme.space2) {
            Capsule().fill(Theme.ink).frame(width: 30, height: 3)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.surface)
                .frame(height: 28)
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.hairline) }
                .overlay(alignment: .bottomLeading) {
                    Capsule().fill(Theme.clay).frame(width: 22, height: 4).padding(5)
                }
            Capsule().fill(Theme.ink3.opacity(0.6)).frame(width: 36, height: 2.5)
            Capsule().fill(Theme.line).frame(height: 2.5)
        }
        .padding(Theme.space3).frame(width: 74, height: 96)
        .background(Theme.bg, in: shape)
        .overlay(alignment: .trailing) {
            if value == "system" {
                Rectangle().fill(Theme.ink).frame(width: 30)
                    .overlay { ThemeIcon(symbol: Icon.nightBadge, size: 13).foregroundStyle(Theme.bg) }
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Theme.line, lineWidth: Theme.rule) }
        .environment(\.colorScheme, dark ? .dark : .light)
        .accessibilityHidden(true)
    }
}

/// 开源字体许可页:展示应用内嵌字体的 OFL 授权文本。
struct FontLicenseView: View {
    private let fonts: [(name: String, resource: String)] = [("思源宋体 Noto Serif CJK", "Noto-OFL"), ("霞鹜文楷 LXGW WenKai", "LXGW-OFL")]
    private let components: [(name: String, license: String, url: String)] = [
        ("Readium Swift Toolkit 3.11.1", "BSD-3-Clause", "https://github.com/readium/swift-toolkit/blob/3.11.1/LICENSE"),
        ("SwiftSoup 2.13.5", "MIT", "https://github.com/scinfu/SwiftSoup/blob/2.13.5/LICENSE"),
        ("ReadiumZIPFoundation 3.0.1", "MIT", "https://github.com/readium/ZIPFoundation/blob/3.0.1/LICENSE"),
        ("ZIPFoundation 原项目（fork 上游）", "MIT", "https://github.com/weichsel/ZIPFoundation"),
        ("SMBClient 0.3.1", "MIT", "https://github.com/kishikawakatsumi/SMBClient/blob/0.3.1/LICENSE"),
        ("Pow 1.0.6", "MIT", "https://github.com/EmergeTools/Pow/blob/1.0.6/LICENSE"),
        ("CryptoSwift 1.10.0", "Zlib（含署名条款）", "https://github.com/krzyzanowskim/CryptoSwift/blob/1.10.0/LICENSE"),
        ("Zip 2.1.2", "MIT", "https://github.com/marmelroy/Zip/blob/2.1.2/LICENSE"),
        ("DifferenceKit 1.3.0", "Apache-2.0", "https://github.com/ra1028/DifferenceKit/blob/1.3.0/LICENSE"),
        ("ReadiumFuzi 4.0.0", "MIT", "https://github.com/readium/Fuzi/blob/4.0.0/LICENSE"),
        ("Lucide 图标", "ISC / MIT（逐图归属见许可）", "https://lucide.dev/license")
    ]
    // Package.resolved contains these optional/host-tool packages; the app does not link their products.
    private let resolvedTools: [(name: String, license: String, url: String)] = [
        ("CSQLite 3.50.4", "Apache-2.0（含 Swift 例外与第三方条款）", "https://github.com/stephencelis/CSQLite/blob/3.50.4/LICENSE"),
        ("ReadiumGCDWebServer 4.0.0", "BSD-3-Clause", "https://github.com/readium/GCDWebServer/blob/4.0.0/LICENSE"),
        ("SQLCipher.swift 4.11.0", "BSD-3-Clause / 社区版条款", "https://github.com/sqlcipher/SQLCipher.swift/blob/4.11.0/LICENSE.md"),
        ("SQLite.swift 0.16.0", "MIT", "https://github.com/stephencelis/SQLite.swift/blob/0.16.0/LICENSE.txt"),
        ("swift-argument-parser 1.0.1", "Apache-2.0（含 Swift 例外）", "https://github.com/apple/swift-argument-parser/blob/1.0.1/LICENSE.txt"),
        ("swift-docc-plugin 1.5.0", "Apache-2.0（含 Swift 例外）", "https://github.com/swiftlang/swift-docc-plugin/blob/1.5.0/LICENSE.txt"),
        ("swift-docc-symbolkit 1.0.0", "Apache-2.0（含 Swift 例外）", "https://github.com/swiftlang/swift-docc-symbolkit/blob/1.0.0/LICENSE.txt")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space5) {
                Masthead(title: "每一份创作，皆有出处", subtitle: "听页使用的开源组件、图标与字体及其许可。", titleSize: 28)
                SectionTitle(text: "开源组件")
                ForEach(components, id: \.name) { component in
                    HairlineRow {
                        VStack(alignment: .leading, spacing: Theme.space1) {
                            Link(component.name, destination: URL(string: component.url)!).foregroundStyle(Theme.clayDeep)
                            Text(component.license).font(Theme.sans(13)).foregroundStyle(Theme.ink3)
                        }.padding(.vertical, Theme.space2)
                    }
                }
                ForEach(["Readium-LICENSE", "Readium-Dependencies-LICENSE", "ZIPFoundation-LICENSE", "SMBClient-LICENSE", "Pow-LICENSE", "Lucide-LICENSE"], id: \.self) { resource in
                    DisclosureGroup(resource) { Text(license(resource)).font(.caption.monospaced()).textSelection(.enabled) }
                }
                DisclosureGroup("依赖解析中的可选组件与构建工具") {
                    ForEach(resolvedTools, id: \.name) { component in
                        VStack(alignment: .leading, spacing: Theme.space1) {
                            Link(component.name, destination: URL(string: component.url)!).foregroundStyle(Theme.clayDeep)
                            Text(component.license).font(.caption).foregroundStyle(Theme.ink2)
                        }
                    }
                }
                SectionTitle(text: "字体")

                ForEach(fonts, id: \.name) { font in
                    VStack(alignment: .leading, spacing: Theme.space2) {
                        SectionTitle(text: font.name)
                        Text(license(font.resource))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.ink2)
                            .textSelection(.enabled)
                            .padding(Theme.space4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    }
                }
                Text("两款字体均以 SIL Open Font License 1.1 授权,可自由用于阅读与嵌入。")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, Theme.inset)
            .padding(.vertical, Theme.space4)
            .padding(.bottom, Theme.space6)
            .frame(maxWidth: Theme.pageWidth)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .foregroundStyle(Theme.ink)
        .navigationTitle("开源组件与字体许可")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func license(_ resource: String) -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可文本缺失,请查看应用包内 Resources/\(resource).txt。" }
        return text
    }
}

/// 隐私政策页:本地文本,不跳转外部。
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space3) {
                Masthead(title: "你的阅读，属于你", subtitle: "了解书籍、语音服务、备份与本机隐私保护。", titleSize: 28)
                policy("数据存储", "听页是纯本地应用,没有账号,也不连接听页服务器。书籍、阅读进度与阅读时长保存在本设备。iCloud Drive 备份由你手动触发,包含当前书架的书籍、资源、进度与书签,由 Apple 账号管理。开启「自动同步阅读进度」时,每本书读到的章节与句子序号(及更新时间、由书名、作者、格式与章数生成的匹配摘要)会通过 iCloud 在你的设备间同步,不含书籍内容,可随时关闭;同步时间由系统决定。")
                policy("阅读统计", "阅读时长按日记录在本设备,仅用于统计图表展示,不会自动上传。")
                policy("第三方服务", "系统声音完全离线朗读。启用云端朗读(智谱 GLM / MiniMax)时,应用使用你自己的 API Key 直接连接对应服务商,当前句子的文本会发送给服务商以合成语音;API Key 仅保存在本机钥匙串。")
                policy("数据导出与删除", "你可以在「我」中导出全部阅读统计,或在「iCloud 备份与还原」中管理备份。移除书籍后,本机副本立即删除。")
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, Theme.space2)
            .padding(.bottom, Theme.space6)
            .frame(maxWidth: Theme.pageWidth)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .foregroundStyle(Theme.ink)
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func policy(_ title: String, _ body: String) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: Theme.space2) {
                SectionTitle(text: title)
                Text(body).font(.subheadline).lineSpacing(4).foregroundStyle(Theme.ink2)
            }
        }
    }
}

/// 阅读统计导出包:按日记录的阅读时长与书架进度快照。
struct ReadingStatsExport: Codable {
    struct Row: Codable {
        let id: String
        let title: String
        let author: String
        let chapterCount: Int
        let percent: String
        let progress: ReadingProgress
    }
    let exportedAt: Date
    let readingSeconds: [String: Double]
    let entries: RowArray
    typealias RowArray = [Row]
    /// 逐次阅读记录（1.14 起）
    var sessions: [ReadingSession]? = nil
}
