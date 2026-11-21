import SwiftUI
import UIKit
import Charts
import UniformTypeIdentifiers

// MARK: - 书籍详情

/// 纸面上的书封、清晰的书籍信息与阅读进度。
struct BookDetailView: View {
    private struct PreviewRequest: Equatable {
        let local: Bool
        let attempt: Int
    }

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
    @State private var previewFailed = false
    @State private var previewAttempt = 0
    @State private var moving = false
    var entry: ShelfEntry? { model.entries.first { $0.id == entryID } }

    var body: some View {
        IndexPage {
            HStack(alignment: .top, spacing: Theme.space2) {
                IndexHeading(title: Text("书籍详情"), large: true)
                Button { dismiss() } label: { ThemeIcon(symbol: Icon.close) }
                    .buttonStyle(IndexActionStyle()).accessibilityLabel("返回书库")
            }
            if let entry {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    hero(entry)
                    actionButtons(entry)
                    IndexRule()
                    readingStats(entry)
                }
                .padding(Theme.space4)
                .indexPanel()
                briefSection(entry)
                contentSection(entry)
                manageSection(entry)
            } else {
                IndexStatus(kind: .empty, title: Text("这本书已不在书架上"))
            }
        }
        .tint(IndexTheme.accent)
        .navigationTitle("书籍详情")
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: true)
        .task(id: PreviewRequest(local: entry?.local == true, attempt: previewAttempt)) { await loadReadingDetails() }
        .navigationDestination(item: $chapterBook) { book in ChapterManagerView(book: book) }
        .fileImporter(isPresented: $repair, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): model.run("正在修复原书") { try await model.repair(entryID, from: url) }
            case .failure(let error) where (error as? CocoaError)?.code == .userCancelled: break
            case .failure(let error): model.message = error.localizedDescription
            }
        }
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
                IndexPage {
                    if let entry {
                        IndexHeading(title: Text(verbatim: entry.title), large: true)
                        introText(entry)
                            .font(.body).lineSpacing(6).foregroundStyle(IndexTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.space4).indexPanel()
                    }
                }
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

    private func hero(_ entry: ShelfEntry) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.space4))
        return layout {
            CoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id],
                      width: 76, usesIndexPalette: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(verbatim: entry.title).font(IndexTheme.editorial(26, relativeTo: .title))
                    .foregroundStyle(IndexTheme.ink).accessibilityAddTraits(.isHeader)
                Text("\(entry.author.isEmpty ? L("佚名") : entry.author) · \(entry.format)")
                    .font(.subheadline).foregroundStyle(IndexTheme.muted)
                if !entry.local {
                    Text("iCloud 藏书").font(.caption).foregroundStyle(IndexTheme.accent)
                } else if entry.started {
                    bookPosition(entry, chapter: entry.progress.chapter)
                        .font(.caption).monospacedDigit().foregroundStyle(IndexTheme.accent)
                        .accessibilityIdentifier("detail.readingProgress")
                } else {
                    Text("待读").font(.caption).foregroundStyle(IndexTheme.accent)
                }
                if entry.local, !entry.isComic, let position = entry.listeningProgress {
                    let listening = chapterUnit(entry) == "页"
                        ? Text("听至第 \(position.chapter + 1) 页") : Text("听至第 \(position.chapter + 1) 章")
                    listening
                        .font(.caption).monospacedDigit().foregroundStyle(IndexTheme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bookPosition(_ entry: ShelfEntry, chapter: Int) -> Text {
        chapterUnit(entry) == "页" ? Text("读至第 \(chapter + 1) 页") : Text("读至第 \(chapter + 1) 章")
    }

    /// 时长沿用逐书会话口径。
    private func readingStats(_ entry: ShelfEntry) -> some View {
        let seconds = model.visibleSessions.filter { $0.bookID == entry.id }.reduce(0) { $0 + $1.seconds }
        let minutes = Int(seconds / 60)
        let duration = minutes >= 60 ? Text("\(minutes / 60)小时\(minutes % 60)分") : Text("\(minutes)分")
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.space3))
        return layout {
            metric(Text(verbatim: entry.percentText), label: Text("进度"))
            metric(duration, label: Text("累计时长"))
            metric(Text(entry.notes.count, format: .number), label: Text("摘记数"))
        }
    }

    private func metric(_ value: Text, label: Text) -> some View {
        VStack(alignment: .leading, spacing: Theme.space1) {
            label.font(.caption).foregroundStyle(IndexTheme.muted)
            value.font(.headline.monospacedDigit()).foregroundStyle(IndexTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func chapterUnit(_ entry: ShelfEntry) -> String {
        entry.isComic || entry.format.uppercased() == "PDF" ? "页" : "章"
    }

    @ViewBuilder
    private func actionButtons(_ entry: ShelfEntry) -> some View {
        if !entry.local {
            NavigationLink { ICloudBackupView() } label: {
                IndexActionLabel(title: "从备份恢复书籍", symbol: Icon.cloud)
            }
            .buttonStyle(IndexActionStyle(role: .primary, expands: true))
        } else {
            VStack(spacing: Theme.space2) {
                Button("打开") { Haptics.light(); model.open(entry) }
                    .buttonStyle(IndexActionStyle(role: .primary, expands: true))
                    .accessibilityIdentifier("detail.reading")
                if !entry.isComic {
                    Button { Haptics.light(); model.listen(entryID) } label: {
                        IndexActionLabel(title: model.player.book?.id == entryID && model.player.playing ? "打开听书" : "听这本书",
                                         symbol: Icon.listen)
                    }
                    .buttonStyle(IndexActionStyle(role: .secondary, expands: true))
                    .accessibilityIdentifier("detail.listen")
                    .accessibilityHint("辅助朗读，保留当前阅读位置")
                }
            }
        }
    }

    private func briefSection(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            IndexHeading(title: Text("关于这本书"))
            introText(entry).font(.subheadline).lineSpacing(4)
                .foregroundStyle(IndexTheme.muted).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
            Button("查看书籍简介") { showingIntro = true }
                .buttonStyle(IndexActionStyle())
        }
        .padding(Theme.space4)
        .indexPanel()
    }

    private func introText(_ entry: ShelfEntry) -> Text {
        if let intro { return Text(verbatim: intro) }
        if loadingPreview && entry.local { return Text("正在载入简介…") }
        if previewFailed && entry.local { return Text("暂时无法读取简介。") }
        return Text(entry.local ? "这本书未提供简介。" : "还原到本机后可查看简介与目录。")
    }

    @ViewBuilder private func contentSection(_ entry: ShelfEntry) -> some View {
        if entry.local {
            VStack(alignment: .leading, spacing: Theme.space2) {
                IndexHeading(title: Text("目录与书摘"))
                VStack(spacing: 0) {
                    Button {
                        Task {
                            do { chapterBook = try await model.loadBook(entryID) }
                            catch { model.message = error.localizedDescription }
                        }
                    } label: {
                        let total = chapterUnit(entry) == "页" ? Text("共 \(entry.chapterCount) 页") : Text("共 \(entry.chapterCount) 章")
                        IndexRowLabel(title: Text("全部目录"), detail: total, symbol: Icon.contents, disclosure: true)
                    }
                    .buttonStyle(PressButtonStyle())
                    .accessibilityIdentifier("detail.contents")
                    chapterPreview(entry)
                    IndexRule()
                    NavigationLink { bookNotes(entry) } label: {
                        IndexRowLabel(title: Text("书摘与笔记"), detail: Text("\(entry.notes.count) 条"),
                                      symbol: Icon.highlight, disclosure: true)
                    }
                    .buttonStyle(PressButtonStyle())
                    .accessibilityIdentifier("detail.notes")
                    IndexRule()
                    NavigationLink { bookBookmarks(entry) } label: {
                        IndexRowLabel(title: Text("阅读书签"), detail: Text("\(entry.bookmarks.count) 个"),
                                      symbol: Icon.bookmark(false), disclosure: true)
                    }
                    .buttonStyle(PressButtonStyle())
                    .accessibilityIdentifier("detail.bookmarks")
                }
                .padding(.horizontal, Theme.space3)
                .indexPanel()
            }
        }
    }

    @ViewBuilder private func chapterPreview(_ entry: ShelfEntry) -> some View {
        if loadingPreview {
            IndexStatus(kind: .loading, title: Text("正在载入目录预览…"))
                .padding(.vertical, Theme.space2)
        } else if previewFailed {
            VStack(alignment: .leading, spacing: Theme.space1) {
                IndexStatus(kind: .failure, title: Text("无法载入目录预览"))
                Button("重新加载") { previewAttempt += 1 }
                    .buttonStyle(IndexActionStyle())
            }
            .padding(.vertical, Theme.space2)
        } else if !chapterTitles.isEmpty {
            let start = min(max(0, entry.progress.chapter), chapterTitles.count - 1)
            ForEach(start..<min(start + 3, chapterTitles.count), id: \.self) { index in
                IndexRule()
                let current = entry.started && index == entry.progress.chapter
                Button {
                    let position = index == entry.progress.chapter ? entry.progress.position : 0
                    model.open(entry, chapter: index, position: position)
                } label: {
                    IndexRowLabel(title: Text(verbatim: chapterTitles[index]),
                                  detail: current ? Text("读到这里") : nil, symbol: current ? Icon.read : nil)
                        .padding(.horizontal, Theme.space2)
                        .background(current ? IndexTheme.wash : .clear, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityIdentifier("detail.chapter.\(index)")
                .accessibilityLabel(current ? Text("继续阅读，\(chapterTitles[index])") : Text("阅读，\(chapterTitles[index])"))
            }
        }
    }

    private func bookNotes(_ entry: ShelfEntry) -> some View {
        List {
            IndexHeading(title: Text(verbatim: entry.title))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            NotesList(entryID: entryID) { note in model.open(entry, target: .init(note)) }
        }
        .indexList()
        .navigationTitle("书摘与笔记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: true)
    }

    private func bookBookmarks(_ entry: ShelfEntry) -> some View {
        List {
            IndexHeading(title: Text(verbatim: entry.title))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            if entry.bookmarks.isEmpty {
                IndexStatus(kind: .empty, title: Text("还没有书签"),
                            detail: Text("阅读时点按顶部书签，留下想回来的位置。"))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                Button("打开") { model.open(entry) }.buttonStyle(IndexActionStyle(role: .primary))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(entry.bookmarks.sorted { $0.date > $1.date }) { bookmark in
                Button { model.open(entry, target: .init(bookmark)) } label: {
                    VStack(alignment: .leading, spacing: Theme.space1) {
                        bookPosition(entry, chapter: bookmark.chapter)
                            .font(.caption.weight(.semibold)).foregroundStyle(IndexTheme.accent)
                        let excerpt = bookmark.excerpt.isEmpty ? Text("回到这个阅读位置") : Text(verbatim: bookmark.excerpt)
                        excerpt.font(.body).foregroundStyle(IndexTheme.ink)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                        Text(bookmark.date, format: .dateTime.year().month().day())
                            .font(.caption).foregroundStyle(IndexTheme.muted)
                    }
                    .padding(.vertical, Theme.space2)
                    .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
                .listRowBackground(IndexTheme.surface)
            }
        }
        .indexList()
        .navigationTitle("阅读书签").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: true)
    }

    private func manageSection(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            IndexHeading(title: Text("书籍管理"))
            VStack(spacing: 0) {
                Button { moving = true } label: {
                    IndexRowLabel(title: Text("分组"), detail: entry.group.map { Text(verbatim: $0) } ?? Text("未分组"),
                                  symbol: Icon.folder, disclosure: true)
                }
                if entry.local {
                    IndexRule()
                    Button { exportBook(entry) } label: {
                        IndexRowLabel(title: Text("导出书籍备份"), symbol: Icon.share)
                    }
                }
                if !entry.sample {
                    if entry.local {
                        IndexRule()
                        Button { repair = true } label: {
                            IndexRowLabel(title: Text("修复图文与封面"), detail: Text("选择同格式的原书文件。"),
                                          symbol: Icon.repair)
                        }
                        if entry.format.uppercased() == "TXT" {
                            IndexRule()
                            Button { model.run("正在重新分章") { try await model.resplit(entryID) } } label: {
                                IndexRowLabel(title: Text("按分章规则重新分章"), symbol: Icon.contents)
                            }
                        }
                    }
                    IndexRule()
                    Button(role: .destructive) { removal = true } label: {
                        HStack {
                            IndexActionLabel(title: "移除书籍…", symbol: Icon.delete)
                            Spacer()
                        }
                        .font(.body.weight(.medium)).foregroundStyle(IndexTheme.danger)
                        .frame(minHeight: Theme.rowMinHeight).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("detail.remove")
                }
            }
            .buttonStyle(PressButtonStyle())
            .padding(.horizontal, Theme.space3)
            .indexPanel()
        }
    }

    /// 简介先显示轻量缓存，目录在后台读取后更新。
    private func loadReadingDetails() async {
        previewFailed = false
        guard entry?.local == true else { intro = nil; chapterTitles = []; loadingPreview = false; return }
        loadingPreview = true
        defer { if !Task.isCancelled { loadingPreview = false } }
        let cached = entry?.intro?.trimmingCharacters(in: .whitespacesAndNewlines)
        intro = cached?.isEmpty == false ? cached : nil
        do {
            let book = try await model.loadBook(entryID)
            guard !Task.isCancelled else { return }
            chapterTitles = book.chapters.map(\.title)
            guard intro == nil else { return }
            let loaded = [book.fields["description"]?.string, book.fields["intro"]?.string]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            intro = loaded
            if let loaded { model.updateEntries([entryID]) { $0.intro = loaded } }
        } catch {
            if !Task.isCancelled { previewFailed = true }
        }
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
            IndexHeading(title: Text(verbatim: book.title),
                         detail: Text("共 \(chapters.count) 章 · 已读 \(read.count) 章"))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            if visibleIndices.isEmpty {
                IndexStatus(kind: .empty, title: Text(query.isEmpty ? "没有章节" : "没有符合条件的章节"))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(visibleIndices, id: \.self) { index in
                chapterRow(index: index, chapter: chapters[index])
                    .listRowBackground(selected.contains(index) || (!selecting && isCurrent(index)) ? IndexTheme.wash : IndexTheme.surface)
            }
        }
        .indexList()
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
            if selecting { selectionActions }
        }
        .onAppear { loadRead() }
    }

    private var selectionActions: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space1))
            : AnyLayout(HStackLayout(spacing: Theme.space2))
        return VStack(alignment: .leading, spacing: Theme.space2) {
            IndexRule()
            VStack(alignment: .leading, spacing: Theme.space2) {
                layout {
                    Text("已选 \(selected.count) 章").font(.subheadline.weight(.semibold))
                        .foregroundStyle(IndexTheme.ink).accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(allVisibleSelected ? "取消当前全选" : query.isEmpty ? "全选章节" : "全选搜索结果") {
                        if allVisibleSelected { selected.subtract(visibleIndices) } else { selected.formUnion(visibleIndices) }
                    }
                    .buttonStyle(IndexActionStyle()).disabled(visibleIndices.isEmpty || marking)
                }
                if marking {
                    IndexStatus(kind: .loading, title: Text("正在保存阅读状态…"))
                } else {
                    layout {
                        Button { mark(true) } label: { IndexActionLabel(title: "标记已读", symbol: Icon.markRead) }
                            .buttonStyle(IndexActionStyle(role: .primary, expands: true))
                        Button { mark(false) } label: { IndexActionLabel(title: "标记未读", symbol: Icon.markUnread) }
                            .buttonStyle(IndexActionStyle(role: .secondary, expands: true))
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .padding(.horizontal, Theme.space4).padding(.bottom, Theme.space2)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .background(IndexTheme.canvas)
    }

    private func chapterRow(index: Int, chapter: Chapter) -> some View {
        let selectedHere = selected.contains(index)
        let current = isCurrent(index)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: Theme.space2))
        return layout {
            Button {
                if selecting {
                    if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                } else if let entry = model.entries.first(where: { $0.id == book.id }) {
                    model.open(entry, chapter: index, position: 0)
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    IndexRowLabel(title: Text(verbatim: chapter.title),
                                  detail: Text(read.contains(index) ? "已读" : "未读"),
                                  symbol: selecting ? Icon.selection(selectedHere) : (current ? Icon.read : nil))
                    if current {
                        Text("读到这里").font(.caption.weight(.semibold)).foregroundStyle(IndexTheme.accent)
                    }
                    Text("共 \(chapter.text.count) 字").font(.caption).foregroundStyle(IndexTheme.muted)
                }
                .padding(.bottom, Theme.space2)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityLabel(selecting
                ? (selectedHere ? Text("取消选择，\(chapter.title)") : Text("选择，\(chapter.title)"))
                : Text("阅读，\(chapter.title)"))
            .accessibilityValue(current ? Text("读到这里") : Text(read.contains(index) ? "已读" : "未读"))
            .accessibilityAddTraits(selecting && selectedHere ? .isSelected : [])

            if !selecting {
                Button { listen(chapter: index) } label: { IndexActionLabel(title: "听此章", symbol: Icon.listen) }
                    .buttonStyle(IndexActionStyle())
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
    @State private var exportError: String?
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
            .alert("无法导出阅读记录", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("确定", role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "") }
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
        SettingsPage(title: "隐私与关于") {
            SettingsGroup(title: "隐私与保护", footer: "隐藏的书只在验证身份后显示，退出 App 后自动重新隐藏。") {
                Toggle(isOn: $appLock) {
                    IndexRowLabel(title: Text("应用锁"), detail: Text("打开时使用\(PrivacyLock.biometryName)验证"),
                                  symbol: Icon.lock(appLock))
                }
                IndexRule()
                Button {
                    if model.hiddenUnlocked { model.hiddenUnlocked = false } else { Task { await model.unlockHidden() } }
                } label: {
                    IndexRowLabel(title: Text(model.hiddenUnlocked ? "重新隐藏私密书籍" : "查看隐藏的书"),
                                  detail: Text("\(model.entries.filter(\.isHidden).count) 本"),
                                  symbol: Icon.visibilityAction(currentlyVisible: model.hiddenUnlocked))
                }
                IndexRule()
                settingsLink(.privacy, icon: Icon.privacy, title: "隐私政策")
            }
            SettingsGroup(title: "数据导出") {
                Button(action: exportStats) {
                    IndexRowLabel(title: Text("导出阅读数据"), symbol: Icon.share)
                }
            }
            SettingsGroup(title: "关于听页", footer: "\(model.entries.count) 本书，保存在本机和你的私人 iCloud。无需注册账号。") {
                IndexRowLabel(title: Text("版本"), detail: Text(verbatim: version + " (" + build + ")"))
                IndexRule()
                settingsLink(.licenses, icon: Icon.license, title: "开源组件与字体许可")
            }
        }
    }

    private func settingsLink(_ route: SettingsDestination, icon: String, title: String) -> some View {
        Button { settingsRoute = route } label: {
            IndexRowLabel(title: Text(L(title)), symbol: icon, disclosure: true)
        }
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
        } catch { exportError = error.localizedDescription }
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
        IndexPage {
            IndexHeading(title: Text("界面外观"), detail: Text("正文的纸色可在「阅读排版」中单独选择。"), large: true)
            VStack(spacing: 0) {
                appearanceOption("system", title: "跟随系统", subtitle: "随设备外观自动切换")
                IndexRule()
                appearanceOption("light", title: "日间", subtitle: "暖纸底色与深青操作")
                IndexRule()
                appearanceOption("dark", title: "夜间", subtitle: "深色纸面与浅色文字")
            }.indexPanel()
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .respectReducedMotion()
    }

    private func appearanceOption(_ value: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        let selected = appearance == value
        return Button {
            Haptics.selection()
            withAnimation(IndexTheme.transition) { appearance = value }
        } label: {
            HStack(spacing: Theme.space3) {
                HStack(spacing: 0) {
                    if value != "dark" { swatch(.light) }
                    if value != "light" { swatch(.dark) }
                }
                .frame(width: 48, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                .accessibilityHidden(true)
                IndexRowLabel(title: Text(title), detail: Text(subtitle))
                if selected { ThemeIcon(symbol: Icon.checkmark).foregroundStyle(IndexTheme.accent).accessibilityHidden(true) }
            }
            .padding(.horizontal, Theme.space3)
            .background(selected ? IndexTheme.wash : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("appearance.\(value)")
    }

    private func swatch(_ style: UIUserInterfaceStyle) -> some View {
        let traits = UITraitCollection(userInterfaceStyle: style)
        return Color(uiColor: UIColor(IndexTheme.canvas).resolvedColor(with: traits))
            .overlay {
                Capsule().fill(Color(uiColor: UIColor(IndexTheme.accent).resolvedColor(with: traits)))
                    .frame(width: 14, height: 4)
            }
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
        SettingsPage(title: "开源组件与字体许可") {
            SettingsGroup(title: "开源组件") {
                ForEach(components, id: \.name) { component in
                    Link(destination: URL(string: component.url)!) {
                        IndexRowLabel(title: Text(verbatim: component.name), detail: Text(verbatim: component.license), disclosure: true)
                    }
                    IndexRule()
                }
                ForEach(["Readium-LICENSE", "Readium-Dependencies-LICENSE", "ZIPFoundation-LICENSE", "SMBClient-LICENSE", "Pow-LICENSE", "Lucide-LICENSE"], id: \.self) { resource in
                    DisclosureGroup(resource) { Text(license(resource)).font(.caption.monospaced()).textSelection(.enabled) }
                        .padding(.vertical, Theme.space2)
                }
                DisclosureGroup("依赖解析中的可选组件与构建工具") {
                    ForEach(resolvedTools, id: \.name) { component in
                        Link(destination: URL(string: component.url)!) {
                            IndexRowLabel(title: Text(verbatim: component.name), detail: Text(verbatim: component.license), disclosure: true)
                        }
                    }
                }
                .padding(.vertical, Theme.space2)
            }
            SettingsGroup(title: "字体", footer: "两款字体均以 SIL Open Font License 1.1 授权,可自由用于阅读与嵌入。") {
                ForEach(fonts, id: \.name) { font in
                    DisclosureGroup(font.name) {
                        Text(license(font.resource)).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    .padding(.vertical, Theme.space2)
                }
            }
        }
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
        SettingsPage(title: "隐私政策") {
            policy("数据存储", "听页是纯本地应用,没有账号,也不连接听页服务器。书籍、阅读进度与阅读时长保存在本设备。iCloud Drive 备份由你手动触发,包含当前书架的书籍、资源、进度与书签,由 Apple 账号管理。开启「自动同步阅读进度」时,每本书读到的章节与句子序号(及更新时间、由书名、作者、格式与章数生成的匹配摘要)会通过 iCloud 在你的设备间同步,不含书籍内容,可随时关闭;同步时间由系统决定。")
            policy("阅读统计", "阅读时长按日记录在本设备,仅用于统计图表展示,不会自动上传。")
            policy("第三方服务", "系统声音完全离线朗读。启用云端朗读(智谱 GLM / MiniMax / Azure / ElevenLabs / 自定义)时,应用使用你自己的 API Key 直接连接对应服务商,当前句子的文本会发送给服务商以合成语音;API Key 仅保存在本机钥匙串。")
            policy("数据导出与删除", "你可以在「我」中导出全部阅读统计,或在「iCloud 备份与还原」中管理备份。移除书籍后,本机副本立即删除。")
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func policy(_ title: String, _ body: String) -> some View {
        SettingsGroup(title: title) {
            Text(L(body)).font(.body).lineSpacing(5).foregroundStyle(IndexTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Theme.space2)
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
