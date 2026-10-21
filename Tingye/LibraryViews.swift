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
    var entry: ShelfEntry? { model.entries.first { $0.id == entryID } }

    var body: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: 0) {
                    hero(entry)
                    briefSection(entry).padding(.top, 24)
                    contentSection(entry).padding(.top, 26)
                    manageSection(entry).padding(.top, 2)
                }
                .padding(.horizontal, Theme.inset)
                .padding(.top, 0)
                .padding(.bottom, 44)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("这本书已不在书架上", systemImage: Icon.emptyBook)
                    .padding(.top, 120)
            }
        }
        .paperBackground()
        .navigationTitle(entry?.title ?? "书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let entry {
                actionButtons(entry)
                    .padding(.horizontal, Theme.inset)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .background(Theme.bg.ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) { InkRule(height: 1.5) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let entry {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                        Text((entry.author.isEmpty ? "佚名" : entry.author) + " · " + entry.format)
                            .font(.caption).foregroundStyle(Theme.ink3).lineLimit(1)
                    }
                }
            }
        }
        .task(id: entry?.local) { await loadIntro() }
        .navigationDestination(item: $chapterBook) { book in ChapterManagerView(book: book) }
        .fileImporter(isPresented: $repair, allowedContentTypes: [.data]) { result in switch result { case .success(let url): model.run("正在修复原书") { try await model.repair(entryID, from: url) }; case .failure(let error): model.message = error.localizedDescription } }
        .confirmationDialog("移除《\(entry?.title ?? "")》?", isPresented: $removal, titleVisibility: .visible) {
            Button("仅删除本机", role: .destructive) { do { try model.removeLocal(entryID); dismiss() } catch { model.message = error.localizedDescription } }
            Button("删除本机和 iCloud", role: .destructive) { model.removeLocalAndICloud(entryID); dismiss() }
        } message: { Text("「仅删除本机」保留 iCloud 备份，之后可还原；「删除本机和 iCloud」会从所有 iCloud 备份快照与进度同步中移除这本书，无法恢复。") }
        .sheet(item: $export) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $showingIntro) {
            NavigationStack {
                ScrollView {
                    if let entry { introSection(entry).padding(Theme.inset) }
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

    /// 真实书封与完整书名，不再把封面颜色放大成整页刊头。
    private func hero(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 24) {
                if !typeSize.isAccessibilitySize {
                    BookCoverView(title: entry.title, color: entry.color, author: entry.author, image: model.covers[entry.id], width: 108)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.title).font(Theme.serifBold(28, relativeTo: .title)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.author.isEmpty ? "佚名" : entry.author).font(.subheadline).foregroundStyle(Theme.ink2)
                    Text(model.category(entry) + " · " + entry.format).font(.caption).foregroundStyle(Theme.ink3)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            detailLayout {
                fact(entry.local ? (entry.started ? "\(Int((entry.readFraction * 100).rounded()))" : "0") : "—", unit: "%", label: entry.local ? "已读" : "iCloud 藏书")
                fact("\(max(1, entry.chapterCount))", unit: "章", label: "篇幅")
                fact("\(entry.progress.chapter + 1)", unit: "章", label: "读到")
            }
            ProgressBar(value: entry.readFraction, height: 3)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .columnRule(Theme.ruleHeavy)
    }

    private var detailLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }
    private func fact(_ value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value + " " + unit).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionButtons(_ entry: ShelfEntry) -> some View {
        if !entry.local {
            NavigationLink { ICloudBackupView() } label: { Text("从备份恢复书籍") }
                .buttonStyle(PrimaryButtonStyle(height: 48))
        } else {
            detailLayout {
                Button { Haptics.light(); model.open(entry) } label: {
                    Text(entry.started ? "继续阅读" : "开始阅读")
                }
                .buttonStyle(PrimaryButtonStyle(height: 48))
                if !entry.isComic {
                    Button { Haptics.light(); model.listen(entryID) } label: {
                        Text(model.player.book?.id == entryID && model.player.playing ? "正在听" : "听书")
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 48))
                    .frame(width: typeSize.isAccessibilitySize ? nil : 118)
                }
            }
        }
    }

    /// 01 简介：三行摘要，轻点看全文。
    private func briefSection(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "简介", number: "01")
            Button { showingIntro = true } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(intro ?? (entry.local ? "这本书未提供简介。" : "还原到本机后可查看简介与目录。"))
                        .font(.subheadline)
                        .lineSpacing(6)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if intro != nil { Text("全文 →").font(.footnote.weight(.medium)).foregroundStyle(Theme.ink) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(intro == nil)
        }
    }

    private func introSection(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "关于这本书", rule: false)
            Text(intro ?? (entry.local ? "这本书未提供简介。" : "还原到本机后可查看简介与目录。"))
                .font(.body)
                .lineSpacing(7)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder private func contentSection(_ entry: ShelfEntry) -> some View {
        if entry.local {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "目录与书摘", number: "02").padding(.bottom, 4)
                Button {
                    Task {
                        do { chapterBook = try await model.loadBook(entryID) }
                        catch { model.message = error.localizedDescription }
                    }
                } label: {
                    detailRow(icon: Icon.contents, title: "目录", subtitle: "\(entry.chapterCount) 章")
                }
                .buttonStyle(PressButtonStyle(scale: 0.99))
                NavigationLink {
                    List { NotesList(entryID: entryID) { note in model.open(entry, chapter: note.chapter, position: note.start) } }
                        .scrollContentBackground(.hidden)
                        .background(Theme.bg)
                        .navigationTitle("书摘与笔记")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.visible, for: .navigationBar)
                        .toolbar(.hidden, for: .tabBar)
        .preference(key: LibraryNavigationHiddenKey.self, value: true)
                } label: {
                    detailRow(icon: Icon.highlight, title: "书摘与笔记", subtitle: "\(entry.notes.count) 条标注 · \(entry.notes.filter { !($0.note ?? "").isEmpty }.count) 篇笔记")
                }
                .buttonStyle(PressButtonStyle(scale: 0.99))
            }
        }
    }

    private func manageSection(_ entry: ShelfEntry) -> some View {
        Menu {
            Button { showingIntro = true } label: { Label("查看书籍简介", systemImage: Icon.info) }
            if entry.local {
                Button { exportBook(entry) } label: { Label("导出书籍备份", systemImage: Icon.share) }
            }
            if !entry.sample {
                if entry.local { Button { repair = true } label: { Label("修复图文与封面", systemImage: Icon.repair) } }
                Divider()
                Button(role: .destructive) { removal = true } label: { Label("移除书籍…", systemImage: Icon.delete) }
            }
        } label: {
            detailRow(icon: Icon.more, title: "导出 / 修复 / 移除", subtitle: "在更多菜单中管理书籍")
        }
        .accessibilityLabel("书籍简介、导出与管理")
    }

    private func detailRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ThemeIcon(symbol: icon, size: 24).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.caption).foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ThemeIcon(symbol: Icon.disclosure, size: 18).foregroundStyle(Theme.ink3)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { RowDivider() }
        .contentShape(Rectangle())
    }

    /// 大书（多图 EPUB 可达上百 MB）优先使用书架轻量目录中的简介缓存，缺失时才在后台读取整本书。
    private func loadIntro() async {
        guard entry?.local == true else { intro = nil; return }
        if let cached = entry?.intro?.trimmingCharacters(in: .whitespacesAndNewlines), !cached.isEmpty {
            intro = cached
            return
        }
        guard let book = try? await model.loadBook(entryID) else { intro = nil; return }
        // EPUB 没有简介时导入为空字符串，不能让它盖掉「未提供简介」的提示。
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
            let packet = BackupPacket(book: book, progress: row.progress)
            try await Task.detached(priority: .userInitiated) { try Integrity.encoder().encode(packet).write(to: url, options: .atomic) }.value
            export = ExportedBook(url: url)
        }
    }
}

extension Book: Hashable { func hash(into hasher: inout Hasher) { hasher.combine(id) } }

struct ChapterManagerView: View {
    let book: Book
    @EnvironmentObject var model: AppModel
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
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(book.title).font(Theme.serifSemibold(23, relativeTo: .title2)).foregroundStyle(Theme.ink)
                    Text("共 \(chapters.count) 章 · 已读 \(read.count) 章")
                        .font(.caption).foregroundStyle(Theme.ink3)
                    Text(selecting ? "轻点章节进行选择，再在底部标记阅读状态。" : "轻点章节开始阅读，或选择「听此章」。")
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                }
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
            }
            Section {
                ForEach(visibleIndices, id: \.self) { index in
                    chapterRow(index: index, chapter: chapters[index]).listRowBackground(Theme.surface)
                }
                if visibleIndices.isEmpty {
                    ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
                VStack(spacing: 10) {
                    HStack {
                        Text("已选 \(selected.count) 章").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        Button(allVisibleSelected ? "取消当前全选" : query.isEmpty ? "全选章节" : "全选搜索结果") {
                            if allVisibleSelected { selected.subtract(visibleIndices) } else { selected.formUnion(visibleIndices) }
                        }
                        .font(.subheadline).frame(minHeight: 44).disabled(visibleIndices.isEmpty)
                    }
                    HStack(spacing: 12) {
                        Button { mark(true) } label: { Label("标记已读", systemImage: Icon.markRead) }
                            .buttonStyle(PrimaryButtonStyle())
                        Button { mark(false) } label: { Label("标记未读", systemImage: Icon.markUnread) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .disabled(selected.isEmpty || marking)
                }
                .padding(.horizontal, Theme.inset).padding(.bottom, 12)
                .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
                .background(Theme.bg)
                .overlay(alignment: .top) { RowDivider() }
            }
        }
        .onAppear { loadRead() }
    }

    private func chapterRow(index: Int, chapter: Chapter) -> some View {
        HStack(spacing: 12) {
            Button {
                if selecting {
                    if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                } else {
                    model.saveProgress(book.id, chapter: index, position: 0)
                    model.selectedBook = book
                }
            } label: {
                HStack(spacing: 12) {
                    if selecting {
                        Image(systemName: Icon.selection(selected.contains(index)))
                            .font(.system(size: 22)).foregroundStyle(selected.contains(index) ? Theme.accent : Theme.ink3)
                            .frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(chapter.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                        Text("\(read.contains(index) ? "已读" : "未读") · 共 \(chapter.text.count) 字")
                            .font(.caption).foregroundStyle(read.contains(index) ? Theme.accent : Theme.ink3)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selecting ? "\(selected.contains(index) ? "取消选择" : "选择")，\(chapter.title)" : "阅读，\(chapter.title)")
            if !selecting {
                Button { listen(chapter: index) } label: {
                    Label("听此章", systemImage: Icon.listen)
                        .font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).frame(minHeight: 44)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("听书，\(chapter.title)")
            }
        }
        .padding(.vertical, 5)
    }

    /// 正在听这本书时只跳章，不重建朗读。
    private func listen(chapter index: Int) {
        model.saveProgress(book.id, chapter: index, position: 0)
        if model.player.book?.id == book.id { model.player.seek(chapter: index, position: 0); if !model.player.playing { model.player.resume() }; model.showingPlayer = true }
        else { model.startListening(book) }
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
    case reading, fonts, voice, appearance, backup, notes, privacy, licenses, profile
}

@ViewBuilder
func settingsDestinationView(_ route: SettingsDestination) -> some View {
    switch route {
    case .reading: ReadingPreferencesView()
    case .fonts: MyFontsView()
    case .voice: VoiceSettingsView()
    case .appearance: AppearanceView()
    case .backup: ICloudBackupView()
    case .notes: AllNotesView()
    case .privacy: PrivacyPolicyView()
    case .licenses: FontLicenseView()
    case .profile: ProfileView()
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
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .scrollContentBackground(.hidden)
            .paperBackground()
            .listStyle(.insetGrouped)
            .listSectionSpacing(4)
            .contentMargins(.horizontal, Theme.inset, for: .scrollContent)
            .contentMargins(.top, 12, for: .scrollContent)
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
        List {
            Section {
                PageMasthead(title: "你的听页", subtitle: "只属于你的阅读方式。", kicker: "PROFILE · 设置", issue: "TINGYE")
                .padding(.top, 12)
                .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 8, trailing: 2))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            settingsPreferences
            settingsData
            settingsAdditional
        }
    }

    private var settingsPreferences: some View {
        Group {
            Section {
                settingsLink(.reading, icon: Icon.typography, color: Theme.accent, title: "阅读排版", subtitle: "字号、行距、纸色与翻页方式")
                settingsLink(.fonts, icon: Icon.fonts, color: Theme.plum, title: "字体管理", subtitle: "查看与导入自己的字体")
            } header: { settingSectionTitle("阅读偏好") }
            Section {
                settingsLink(.voice, icon: Icon.voice, color: Theme.jade, title: "声音与朗读", subtitle: "语音服务、音色与朗读设置")
                settingsLink(.appearance, icon: Icon.appearance, color: Theme.ochre, title: "外观模式", value: appearanceName, disclosure: false)
            } header: { settingSectionTitle("听书与外观") }
        }
    }

    private var settingsData: some View {
        Section {
            settingsLink(.backup, icon: Icon.cloud, title: "备份与同步", subtitle: "书库备份与阅读进度同步")
                .accessibilityValue(syncProgress ? "阅读进度同步已开启" : "阅读进度同步已关闭")
            Button("导出阅读数据", action: exportStats)
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            Button("清除缓存…") { clearingCache = true }
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: { settingSectionTitle("数据与同步") }
    }

    private var settingsAdditional: some View {
        Group {
            Section {
                Toggle(isOn: $appLock) {
                    settingsRow(icon: Icon.lock(appLock), title: "应用锁", subtitle: "打开时使用\(PrivacyLock.biometryName)验证", disclosure: false)
                }
                .frame(minHeight: 60)
                .overlay(alignment: .bottom) { RowDivider() }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                Button {
                    if model.hiddenUnlocked { model.hiddenUnlocked = false } else { Task { await model.unlockHidden() } }
                } label: {
                    settingsRow(icon: Icon.visibilityAction(currentlyVisible: model.hiddenUnlocked), title: model.hiddenUnlocked ? "重新隐藏私密书籍" : "查看隐藏的书", value: "\(model.entries.filter(\.isHidden).count) 本", disclosure: false)
                        .frame(minHeight: 56)
                        .overlay(alignment: .bottom) { RowDivider() }
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                settingsLink(.privacy, icon: Icon.privacy, title: "隐私政策")
            } header: { settingSectionTitle("隐私与保护") } footer: {
                Text("隐藏的书只在验证身份后显示，退出 App 后自动重新隐藏。")
                    .font(.caption).foregroundStyle(Theme.ink3)
            }
            Section {
                settingsLink(.notes, icon: Icon.highlight, color: Theme.gold, title: "全部书摘与笔记", value: "\(model.noteCount) 条")
            } header: { settingSectionTitle("阅读资料") }
            Section {
                settingsRow(title: "版本", value: version + " (" + build + ")", disclosure: false)
                    .frame(minHeight: 56)
                    .overlay(alignment: .bottom) { RowDivider() }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                settingsLink(.licenses, icon: Icon.license, color: Theme.ink2, title: "开源字体许可")
            } header: { settingSectionTitle("关于听页") } footer: {
                Text("\(model.entries.count) 本书，保存在本机和你的私人 iCloud。无需注册账号。")
                    .font(.caption).foregroundStyle(Theme.ink3)
            }
        }
    }

    private func settingSectionTitle(_ title: String) -> some View {
        let order = ["阅读偏好", "听书与外观", "数据与同步", "隐私与保护", "阅读资料", "关于听页"]
        let number = order.firstIndex(of: title).map { String(format: "%02d", $0 + 1) }
        return SectionTitle(text: title, number: number)
            .textCase(nil)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .listRowInsets(EdgeInsets())
    }

    private func settingsLink(_ route: SettingsDestination, icon: String? = nil, color: Color = Theme.accent, title: String, subtitle: String? = nil, value: String? = nil, disclosure: Bool = true) -> some View {
        Button { settingsRoute = route } label: {
            settingsRow(icon: icon, color: color, title: title, subtitle: subtitle, value: value, disclosure: disclosure)
                .padding(.horizontal, 16)
                .frame(minHeight: subtitle == nil ? 52 : 64)
                .overlay(alignment: .bottom) { RowDivider() }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func settingsRow(icon: String? = nil, color: Color = Theme.accent, title: String, subtitle: String? = nil, value: String? = nil, disclosure: Bool = true) -> some View {
        HStack(spacing: 12) {
            if let icon {
                SettingsIcon(systemName: icon, color: color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.ink3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value { Text(value).font(.caption).foregroundStyle(Theme.ink3).lineLimit(1) }
            if disclosure { ThemeIcon(symbol: Icon.disclosure, size: 16).foregroundStyle(Theme.ink3) }
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
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("让界面，合你的光。")
                        .font(Theme.serifSemibold(23, relativeTo: .title2))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("暖纸与石墨，顺应每一刻的光。")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink3)
                }
                VStack(spacing: 12) {
                    appearanceOption("system", title: "跟随系统", subtitle: "随设备外观自动切换")
                    appearanceOption("light", title: "日间", subtitle: "暖纸底色，石墨文字与陶橙标记")
                    appearanceOption("dark", title: "夜间", subtitle: "柔和石墨底，安静地读入夜色")
                }
                Text("正文的纸色可在「阅读排版」中单独选择。")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, Theme.inset)
            .padding(.vertical, 24)
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
            HStack(spacing: 18) {
                appearancePreview(value)
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: Icon.selection(selected))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.line)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
            .overlay { if selected { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1) } }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(PressButtonStyle(scale: 0.99))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("appearance.\(value)")
    }

    private func appearancePreview(_ value: String) -> some View {
        let dark = value == "dark"
        let background = dark ? Color(hex: 0x191B1A) : Color(hex: 0xF6F3EC)
        let foreground = dark ? Color(hex: 0xF2EFE6) : Color(hex: 0x292D29)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 3) {
                Circle().fill(foreground.opacity(0.55)).frame(width: 4, height: 4)
                Capsule().fill(foreground.opacity(0.2)).frame(width: 21, height: 3)
            }
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: dark ? 0x333A32 : 0xEBE3D2)).frame(height: 25)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(hex: dark ? 0xF0AD88 : 0xA44A2C)).frame(width: 11, height: 15).padding(.leading, 6)
                }
            Capsule().fill(foreground.opacity(0.35)).frame(width: 40, height: 3)
            Capsule().fill(foreground.opacity(0.18)).frame(height: 3)
            Capsule().fill(foreground.opacity(0.18)).frame(width: 32, height: 3)
        }
        .padding(11)
        .frame(width: 74, height: 98)
        .background(background)
        .overlay(alignment: .trailing) {
            if value == "system" {
                Rectangle().fill(Color(hex: 0x191B1A)).frame(width: 30)
                    .overlay { Image(systemName: Icon.nightBadge).font(.caption).foregroundStyle(Color(hex: 0xF0AD88)) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(foreground.opacity(0.1), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// 开源字体许可页:展示应用内嵌字体的 OFL 授权文本。
struct FontLicenseView: View {
    private let fonts: [(name: String, resource: String)] = [("思源宋体 Noto Serif CJK", "Noto-OFL"), ("霞鹜文楷 LXGW WenKai", "LXGW-OFL")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(fonts, id: \.name) { font in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: font.name)
                        Text(license(font.resource))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.ink2)
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    }
                }
                Text("两款字体均以 SIL Open Font License 1.1 授权,可自由用于阅读与嵌入。")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, Theme.inset)
            .padding(.vertical, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: Theme.pageWidth)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .foregroundStyle(Theme.ink)
        .navigationTitle("开源字体许可")
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
            VStack(alignment: .leading, spacing: 12) {
                policy("数据存储", "听页是纯本地应用,没有账号,也不连接听页服务器。书籍、阅读进度与阅读时长保存在本设备。iCloud Drive 备份由你手动触发,包含当前书架的书籍、资源、进度与书签,由 Apple 账号管理。开启「自动同步阅读进度」时,每本书读到的章节与句子序号(及更新时间、由书名、作者、格式与章数生成的匹配摘要)会通过 iCloud 在你的设备间同步,不含书籍内容,可随时关闭;同步时间由系统决定。")
                policy("阅读统计", "阅读时长按日记录在本设备,仅用于统计图表展示,不会自动上传。")
                policy("第三方服务", "系统声音完全离线朗读。启用云端朗读(智谱 GLM / MiniMax)时,应用使用你自己的 API Key 直接连接对应服务商,当前句子的文本会发送给服务商以合成语音;API Key 仅保存在本机钥匙串。")
                policy("数据导出与删除", "你可以在「我」中导出全部阅读统计,或在「iCloud 备份与还原」中管理备份。移除书籍后,本机副本立即删除。")
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: Theme.pageWidth)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .foregroundStyle(Theme.ink)
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func policy(_ title: String, _ body: String) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
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
