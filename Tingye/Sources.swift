import SwiftUI
import Network
import UniformTypeIdentifiers

// MARK: - 书源（参照 PureLibro：WiFi 传书、WebDAV、OPDS、文件 App / 网盘 / SMB）

/// 已保存的远程书库。密码不在这里，存在钥匙串（键 `source.<id>`）。
struct RemoteSource: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case webdav, opds, smb }
    var id = UUID().uuidString
    var kind: Kind
    var name: String
    var url: String
    var username: String = ""
    var password: String { (try? Keychain.data("source." + id)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    var baseURL: URL? { URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) }
    /// 基本认证头（WebDAV 与需要登录的 OPDS 共用）
    var authorization: String? {
        guard !username.isEmpty else { return nil }
        return "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}

/// 书源密码仅用于配置的源站；书目链接和 HTTP 重定向都不能扩大认证范围。
final class SourceHTTPClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let baseURL: URL?
    private let authorization: String?

    init(baseURL: URL?, authorization: String?) {
        self.baseURL = baseURL; self.authorization = authorization
    }

    convenience init(source: RemoteSource) {
        self.init(baseURL: source.baseURL, authorization: source.authorization)
    }

    func authorized(_ request: URLRequest) -> URLRequest {
        var result = request
        result.setValue(Self.sameOrigin(baseURL, request.url) ? authorization : nil, forHTTPHeaderField: "Authorization")
        return result
    }

    private static func sameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs, let scheme = lhs.scheme?.lowercased(), ["http", "https"].contains(scheme),
              scheme == rhs.scheme?.lowercased(), let host = lhs.host?.lowercased(), host == rhs.host?.lowercased() else { return false }
        let defaultPort = scheme == "https" ? 443 : 80
        return (lhs.port ?? defaultPort) == (rhs.port ?? defaultPort)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let session = session(); defer { session.invalidateAndCancel() }
        return try await session.data(for: authorized(request))
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        let session = session(); defer { session.invalidateAndCancel() }
        return try await session.download(for: authorized(request))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(authorized(request))
    }
}

enum SourceStore {
    private static let key = "sources.list"
    static func load() -> [RemoteSource] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RemoteSource].self, from: data)) ?? []
    }
    static func save(_ list: [RemoteSource]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
    static func setPassword(_ password: String, for id: String) {
        if password.isEmpty { try? Keychain.remove("source." + id) }
        else { try? Keychain.save(Data(password.utf8), key: "source." + id) }
    }
}

/// 可以直接导入的扩展名
enum ImportableFile {
    static let extensions: Set<String> = ["epub", "txt", "text", "pdf", "html", "htm", "xhtml", "md", "markdown", "docx", "json", "mobi", "azw3", "azw", "cbz", "cbt", "cbr", "cb7", "zip"]
    static func accepts(_ name: String) -> Bool { extensions.contains((name as NSString).pathExtension.lowercased()) }
}

struct SourcesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sources = SourceStore.load()
    @State private var editing: RemoteSource?
    @State private var removing: RemoteSource?
    @State private var wifi = false

    var body: some View {
        SettingsPage(title: "添加书籍", detail: "支持本机文件、局域网传书与远程书库。导入后保存在本机。") {
            SettingsGroup(
                title: "本机与云盘",
                footer: "支持 EPUB、TXT、PDF、MOBI、AZW3、DOCX、Markdown、CBZ、CBT 等格式。多本书请用批量导入。"
            ) {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    SourceActionRow(icon: Icon.folder, title: "从文件导入", subtitle: "本机、iCloud 云盘或已挂载网盘", isCard: false, disclosure: false)
                    // 文件选择器不在本 sheet 内呈现：登记请求后关闭面板，onDismiss 释放占用，再由 StudyRootView 消费。
                    Button("选择文件") { model.requestFileImport(); dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.busy)
                        .accessibilityIdentifier("sources.importFile")
                    Button("批量导入文件") { model.requestFileImport(multiple: true); dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.busy)
                        .accessibilityIdentifier("sources.importBatch")
                }
                .padding(.vertical, 4)
            }

            SettingsGroup(title: "局域网传书") {
                NavigationLink(value: "wifi-transfer") {
                    SourceActionRow(icon: Icon.wifi, title: "从电脑传书", subtitle: "同一 Wi-Fi 下用浏览器发送文件", isCard: false)
                }
                .buttonStyle(.plain)
            }

            if !sources.isEmpty {
                SettingsGroup(title: "已连接的远程书库（\(sources.count)）", footer: "连接只保存在本机。移除连接不会删除服务器文件或已导入书籍。") {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        HairlineRow(showsDivider: index < sources.count - 1) {
                            HStack(spacing: 0) {
                                NavigationLink {
                                    switch source.kind {
                                    case .webdav: WebDAVBrowser(source: source, path: "")
                                    case .smb: SMBBrowser(source: source, share: nil, path: "")
                                    case .opds: OPDSBrowser(source: source, url: source.baseURL, title: source.name)
                                    }
                                } label: {
                                    SourceActionRow(icon: source.kind == .opds ? Icon.catalog : Icon.server,
                                                    title: source.name, subtitle: source.baseURL?.host() ?? source.url, isCard: false)
                                }
                                Menu {
                                    Button { editing = source } label: { Label { Text("编辑连接") } icon: { ThemeIcon(symbol: Icon.edit) } }
                                    Button(role: .destructive) { removing = source } label: { Label { Text("移除连接") } icon: { ThemeIcon(symbol: Icon.delete) } }
                                } label: {
                                    ThemeIcon(symbol: Icon.moreCircle, size: 19).foregroundStyle(Theme.ink2)
                                        .frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize).contentShape(Rectangle())
                                }
                                .accessibilityLabel("管理书库：\(source.name)")
                            }
                        }
                        .contextMenu {
                            Button { editing = source } label: { Label { Text("编辑连接") } icon: { ThemeIcon(symbol: Icon.edit) } }
                            Button(role: .destructive) { removing = source } label: { Label { Text("移除连接") } icon: { ThemeIcon(symbol: Icon.delete) } }
                        }
                    }
                }
            }

            SettingsGroup(title: sources.isEmpty ? "连接远程书库" : "添加新连接") {
                HairlineRow {
                    Button { editing = RemoteSource(kind: .webdav, name: "", url: "https://") } label: {
                        SourceActionRow(icon: Icon.server, title: "WebDAV", subtitle: "坚果云、群晖、Nextcloud 等文件服务器", isCard: false)
                    }
                }
                HairlineRow {
                    Button { editing = RemoteSource(kind: .smb, name: "", url: "smb://") } label: {
                        SourceActionRow(icon: Icon.server, title: "SMB", subtitle: "局域网 NAS、电脑共享文件夹", isCard: false)
                    }
                    .accessibilityIdentifier("sources.addSMB")
                }
                HairlineRow(showsDivider: false) {
                    Button { editing = RemoteSource(kind: .opds, name: "", url: "https://") } label: {
                        SourceActionRow(icon: Icon.catalog, title: "OPDS", subtitle: "Calibre-Web、Talebook 等书目服务", isCard: false)
                    }
                }
            }

            if let report = model.importReport {
                SettingsGroup(title: "导入记录") {
                    NavigationLink { ImportResultsView() } label: {
                        SourceActionRow(icon: Icon.importFile, title: "最近导入结果", subtitle: report.summary, isCard: false)
                    }.buttonStyle(.plain)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(for: String.self) { route in
            if route == "wifi-transfer" { WiFiTransferView() }
        }
        .navigationDestination(isPresented: $wifi) { WiFiTransferView() }
        #if DEBUG
        .task {
            if UIReview.screen == "sources-wifi" { wifi = true }
            if UIReview.screen == "sources-webdav" { editing = RemoteSource(kind: .webdav, name: "", url: "https://") }
        }
        #endif
        .sheet(item: $editing) { source in
            SourceEditor(source: source) { saved, password in
                if let i = sources.firstIndex(where: { $0.id == saved.id }) { sources[i] = saved } else { sources.append(saved) }
                SourceStore.setPassword(password, for: saved.id)
                SourceStore.save(sources)
            }
        }
        .confirmationDialog("移除书库连接？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("移除连接", role: .destructive) {
                if let source = removing { remove(source) }
                removing = nil
            }
            Button("取消", role: .cancel) { removing = nil }
        } message: { Text("将移除「\(removing?.name ?? "")」的地址和本机登录凭据。服务器文件及已导入书籍会保留。") }
    }

    private func remove(_ source: RemoteSource) {
        sources.removeAll { $0.id == source.id }
        SourceStore.setPassword("", for: source.id)
        SourceStore.save(sources)
    }
}

/// 导入面板：书库页头打开，本机文件、电脑传书与远程书库收进同一个系统材料 sheet。
struct ImportHubView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SourcesView()
                .sheetSurface()
                .navigationTitle("添加书籍")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .tint(Theme.accent)
        .feedbackOverlay()
        .respectReducedMotion()
    }
}

private struct SourceActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isCard = true
    var disclosure = true
    var body: some View {
        if isCard { PaperCard { content } }
        else { content }
    }
    private var content: some View {
        HStack(spacing: Theme.space3) {
            ThemeIcon(symbol: icon, size: 20).foregroundStyle(Theme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(L(subtitle)).font(.footnote).foregroundStyle(Theme.ink2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if disclosure { ThemeIcon(symbol: Icon.disclosure, size: 13).foregroundStyle(Theme.ink4) }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 48).contentShape(Rectangle())
    }
}

private struct SourceEditor: View {
    @State var source: RemoteSource
    let onSave: (RemoteSource, String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var password = ""
    private var validAddress: Bool {
        if source.kind == .smb { return SMBAccess.target(source.url) != nil }
        return ["http", "https"].contains(source.baseURL?.scheme?.lowercased() ?? "") && source.baseURL?.host() != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("名称") {
                        TextField("选填，默认使用主机名", text: $source.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(source.kind == .opds ? "书目地址" : "服务器地址") {
                        TextField(source.kind == .smb ? "smb://192.168.1.10" : "https://", text: $source.url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("书库信息")
                } footer: {
                    if !validAddress && source.url.count > 8 {
                        Text(source.kind == .smb ? "请填写有效的 smb:// 主机地址。" : "请填写完整的 http:// 或 https:// 地址。")
                            .foregroundStyle(Theme.danger)
                    }
                }
                .listRowBackground(Theme.sheetCard)

                Section {
                    LabeledContent("用户名") {
                        TextField("选填", text: $source.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("密码") {
                        SecureField("选填 / 应用密码", text: $password)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("访问凭据（选填）")
                } footer: {
                    Text(source.kind == .smb ? "填写 smb:// 加 NAS 或电脑的局域网地址，共享文件夹在连接后选择。不填用户名则以访客登录。" : source.kind == .webdav ? "坚果云等服务请使用第三方应用管理中生成的应用密码。密码仅保存在本机钥匙串。" : "多数 OPDS 服务无需登录；开启访问控制的书库请填写账号。")
                }
                .listRowBackground(Theme.sheetCard)
            }
            .editorialList()
            .sheetSurface()
            .navigationTitle(["webdav": "连接 WebDAV", "smb": "连接 SMB", "opds": "连接 OPDS"][source.kind.rawValue] ?? "连接书库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("保存连接") {
                    if source.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        source.name = SMBAccess.target(source.url)?.host ?? source.baseURL?.host() ?? source.kind.rawValue.uppercased()
                    }
                    onSave(source, password)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!validAddress)
                .padding(.horizontal, Theme.insetCompact)
                .padding(.vertical, Theme.space3)
                .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
                .barMaterialBackground()
            }
            .onAppear { password = source.password }
        }
    }
}

// MARK: - 远程下载后导入

extension AppModel {
    /// 下载一个远程文件到临时目录并导入书库
    func importRemote(_ url: URL, name: String, source: RemoteSource) {
        run("正在下载《\((name as NSString).deletingPathExtension)》") { [self] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            let (temp, response) = try await SourceHTTPClient(source: source).download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ReaderError.message("下载失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。")
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("remote-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            var fileName = (name as NSString).lastPathComponent
            if (fileName as NSString).pathExtension.isEmpty, let suggested = response.suggestedFilename { fileName = suggested }
            let target = folder.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: temp, to: target)
            try await importWithFeedback([target])
        }
    }
}

// MARK: - WebDAV

struct WebDAVBrowser: View {
    let source: RemoteSource
    let path: String
    @EnvironmentObject var model: AppModel
    @State private var items: [WebDAVItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    private var shown: [WebDAVItem] { query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            if let error {
                Section {
                    EditorialNotice(title: "连接暂时未完成", detail: error, kind: .failure)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    Button("重新加载") { Task { await load() } }.disabled(loading)
                        .listRowBackground(Theme.groupedCard)
                }
            }
            if !shown.isEmpty {
                Section {
                    ForEach(shown) { item in
                        if item.isFolder {
                            NavigationLink { WebDAVBrowser(source: source, path: item.path) } label: { row(item) }
                        } else {
                            Button { download(item) } label: { row(item) }
                                .buttonStyle(.plain)
                                .disabled(!ImportableFile.accepts(item.name) || model.busy)
                        }
                    }
                    .listRowBackground(Theme.groupedCard)
                } header: {
                    Text(path.isEmpty ? "WebDAV · \(source.name)" : (path.removingPercentEncoding ?? path))
                }
            }
        }
        .overlay {
            if loading { EmptyState(title: "正在连接远程文件…", detail: source.name, state: .loading) }
            else if error == nil && shown.isEmpty {
                EmptyState(title: query.isEmpty ? "空文件夹" : "未找到匹配文件", detail: "", symbol: query.isEmpty ? Icon.folder : Icon.search)
            }
        }
        .editorialList()
        .navigationTitle(path.isEmpty ? source.name : (path as NSString).lastPathComponent.removingPercentEncoding ?? path)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $query, prompt: "在当前文件夹中搜索")
        .refreshable { await load() }
        .task { await load() }
    }
    private func row(_ item: WebDAVItem) -> some View {
        let importable = ImportableFile.accepts(item.name)
        return EditorialRow(
            title: item.name,
            detail: item.isFolder ? "文件夹" : item.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
            value: item.isFolder ? nil : (importable ? "导入" : "不支持"),
            symbol: item.isFolder ? Icon.folder : Icon.document,
            disclosure: false
        )
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { items = try await WebDAV.list(source, path: path); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func download(_ item: WebDAVItem) {
        guard let url = WebDAV.url(source, path: item.path) else { return }
        model.importRemote(url, name: item.name, source: source)
    }
}

struct WebDAVItem: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let isFolder: Bool
    let size: Int?
}

enum WebDAV {
    static func url(_ source: RemoteSource, path: String) -> URL? {
        guard let base = source.baseURL else { return nil }
        if path.isEmpty { return base }
        if path.hasPrefix("/") { var c = URLComponents(url: base, resolvingAgainstBaseURL: false); c?.percentEncodedPath = path; return c?.url }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// PROPFIND Depth: 1，按「文件夹在前、名称排序」返回下一级条目
    static func list(_ source: RemoteSource, path: String) async throws -> [WebDAVItem] {
        guard let url = url(source, path: path) else { throw ReaderError.message("WebDAV 地址无效。") }
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.timeoutInterval = 30
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:getcontentlength/><d:resourcetype/></d:prop></d:propfind>"#.utf8)
        let (data, response) = try await SourceHTTPClient(source: source).data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw ReaderError.message("用户名或密码不正确（401）。") }
        guard status == 207 || (200..<300).contains(status) else { throw ReaderError.message("WebDAV 请求失败（HTTP \(status)）。") }
        let selfPath = url.path(percentEncoded: true)
        let parsed = MultiStatusParser.parse(data)
        return parsed.compactMap { item -> WebDAVItem? in
            let href = URL(string: item.href, relativeTo: url)?.path(percentEncoded: true) ?? item.href
            guard href.trimmingCharacters(in: CharacterSet(charactersIn: "/")) != selfPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return nil }
            let raw = (href as NSString).lastPathComponent
            let name = item.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? raw.removingPercentEncoding ?? raw
            guard !name.hasPrefix(".") else { return nil }
            return WebDAVItem(path: href, name: name, isFolder: item.collection, size: item.length)
        }
        .sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
    }

    private final class MultiStatusParser: NSObject, XMLParserDelegate {
        struct Item { var href = ""; var displayName: String?; var length: Int?; var collection = false }
        private var items: [Item] = []
        private var current: Item?
        private var text = ""
        static func parse(_ data: Data) -> [Item] {
            let handler = MultiStatusParser()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = handler
            parser.parse()
            return handler.items
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            if name == "response" { current = Item() }
            if name == "collection" { current?.collection = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "href": current?.href = value
            case "displayname": current?.displayName = value
            case "getcontentlength": current?.length = Int(value)
            case "response": if let current { items.append(current) }; current = nil
            default: break
            }
        }
    }
}

// MARK: - OPDS

struct OPDSBrowser: View {
    let source: RemoteSource
    let url: URL?
    let title: String
    @EnvironmentObject var model: AppModel
    @State private var feed: OPDSFeed?
    @State private var loading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var remoteSearchTemplate: String?
    @State private var showingSearchResults = false
    @State private var loadedURL: URL?
    @State private var lastAttemptURL: URL?
    @State private var lastAttemptWasSearch = false
    var body: some View {
        List {
            if let error {
                Section {
                    EditorialNotice(title: "连接暂时未完成", detail: error, kind: .failure)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    Button("重试此请求") { Task { await load(lastAttemptURL ?? url, searchResults: lastAttemptWasSearch) } }
                        .disabled(loading)
                        .listRowBackground(Theme.groupedCard)
                }
            }
            if showingSearchResults {
                Section {
                    Button("返回全部书目") { searchText = ""; Task { await load(url) } }
                        .disabled(loading)
                        .listRowBackground(Theme.groupedCard)
                }
            }
            if let feed {
                let matching = feed.entries.filter { searchText.isEmpty || remoteSearchTemplate != nil || ($0.title + $0.author).localizedCaseInsensitiveContains(searchText) }
                if !loading && matching.isEmpty {
                    EmptyState(title: "这里还没有书目", detail: "可以返回上一级分类，或下拉重新加载。", symbol: Icon.catalog)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if !matching.isEmpty {
                    Section {
                        ForEach(matching) { entry in
                            if let acquisition = entry.acquisition {
                                Button { model.importRemote(acquisition.url, name: entry.title + "." + acquisition.fileExtension, source: source) } label: { bookRow(entry, acquisition) }
                                    .buttonStyle(.plain)
                                    .disabled(model.busy)
                            } else if let next = entry.navigation {
                                NavigationLink { OPDSBrowser(source: source, url: next, title: entry.title) } label: {
                                    SourceActionRow(icon: Icon.folder, title: entry.title,
                                                    subtitle: entry.summary.isEmpty ? "浏览书目" : entry.summary, isCard: false, disclosure: false)
                                }
                            }
                        }
                        .listRowBackground(Theme.groupedCard)
                    }
                }
                if let next = feed.next {
                    Section {
                        NavigationLink { OPDSBrowser(source: source, url: next, title: title) } label: {
                            Label { Text("下一页") } icon: { ThemeIcon(symbol: Icon.nextDirection) }.foregroundStyle(Theme.accent)
                        }
                        .listRowBackground(Theme.groupedCard)
                    }
                }
            }
        }
        .overlay {
            if loading { EmptyState(title: "正在读取书目…", detail: title, state: .loading) }
        }
        .editorialList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $searchText, prompt: remoteSearchTemplate == nil ? "筛选当前书目" : "搜索远程书目")
        .onSubmit(of: .search) {
            guard let template = remoteSearchTemplate, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let encoded = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))),
                  let target = URL(string: template.replacingOccurrences(of: "{searchTerms}", with: encoded), relativeTo: url)?.absoluteURL else { return }
            Task { await load(target, searchResults: true) }
        }
        .refreshable { await load(loadedURL ?? url, searchResults: showingSearchResults) }
        .task { await load(url) }
    }
    private func bookRow(_ entry: OPDSEntry, _ acquisition: OPDSEntry.Link) -> some View {
        HStack(spacing: Theme.space3) {
            AsyncImage(url: entry.thumbnail) { image in image.resizable().scaledToFill() } placeholder: { CoverView(title: entry.title, color: "gray", width: 44) }
                .frame(width: 44, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius(44), style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                if !entry.author.isEmpty { Text(entry.author).font(.caption).foregroundStyle(Theme.ink2).lineLimit(1) }
                SealBadge(text: acquisition.fileExtension.uppercased())
            }
            Spacer()
            Label { Text("导入") } icon: { ThemeIcon(symbol: Icon.downloadFile, size: 16) }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: Theme.iconButtonSize, minHeight: Theme.iconButtonSize)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    private func load(_ target: URL?, searchResults: Bool = false) async {
        guard let target else { error = "OPDS 地址无效。"; loading = false; return }
        lastAttemptURL = target
        lastAttemptWasSearch = searchResults
        loading = true; defer { loading = false }
        do {
            var request = URLRequest(url: target)
            request.timeoutInterval = 30
            let client = SourceHTTPClient(source: source)
            let (data, response) = try await client.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 { throw ReaderError.message("需要登录，请在书源里填写用户名和密码（401）。") }
            guard (200..<300).contains(status) else { throw ReaderError.message("OPDS 请求失败（HTTP \(status)）。") }
            var parsed = OPDSFeed.parse(data, base: response.url ?? target)
            // OpenSearch 描述文件：再取一次得到真正的搜索模板
            if parsed.searchTemplate == nil, let description = parsed.searchDescription {
                let r = URLRequest(url: description)
                if let (d, _) = try? await client.data(for: r), let xml = String(data: d, encoding: .utf8),
                   let range = xml.range(of: #"template="([^"]+)""#, options: .regularExpression) {
                    parsed.searchTemplate = String(xml[range]).replacingOccurrences(of: "template=\"", with: "").replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "&amp;", with: "&")
                }
            }
            if !searchResults { remoteSearchTemplate = parsed.searchTemplate }
            feed = parsed
            loadedURL = target
            showingSearchResults = searchResults
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct OPDSEntry: Identifiable, Sendable {
    struct Link: Sendable { let url: URL; let type: String; let rel: String
        var fileExtension: String {
            let map = ["application/epub+zip": "epub", "application/pdf": "pdf", "text/plain": "txt", "application/x-mobipocket-ebook": "mobi",
                       "application/vnd.amazon.ebook": "azw3", "application/x-mobi8-ebook": "azw3", "application/vnd.comicbook+zip": "cbz", "application/x-cbz": "cbz",
                       "application/vnd.comicbook+tar": "cbt", "application/x-cbt": "cbt", "application/vnd.comicbook+rar": "cbr", "application/x-cbr": "cbr", "application/x-cb7": "cb7", "application/zip": "zip"]
            if let ext = map[type.components(separatedBy: ";").first ?? type] { return ext }
            let ext = url.pathExtension.lowercased()
            return ext.isEmpty ? "epub" : ext
        }
    }
    let id = UUID()
    var title = ""
    var author = ""
    var summary = ""
    var links: [Link] = []
    /// 优先 EPUB，其次其他可导入格式
    var acquisition: Link? {
        let candidates = links.filter { $0.rel.contains("acquisition") && ImportableFile.extensions.contains($0.fileExtension) }
        return candidates.first { $0.fileExtension == "epub" } ?? candidates.first
    }
    var navigation: URL? { links.first { $0.type.contains("atom+xml") || $0.type.contains("opds") || $0.rel == "subsection" }?.url }
    var thumbnail: URL? { (links.first { $0.rel.contains("thumbnail") } ?? links.first { $0.rel.contains("image") })?.url }
}

struct OPDSFeed: Sendable {
    var entries: [OPDSEntry] = []
    var next: URL?
    var searchTemplate: String?
    var searchDescription: URL?

    static func parse(_ data: Data, base: URL) -> OPDSFeed {
        let handler = Parser(base: base)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = handler
        parser.parse()
        return handler.feed
    }

    private final class Parser: NSObject, XMLParserDelegate {
        let base: URL
        var feed = OPDSFeed()
        var entry: OPDSEntry?
        var inAuthor = false
        var text = ""
        init(base: URL) { self.base = base }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "entry": entry = OPDSEntry()
            case "author": inAuthor = true
            case "link":
                guard let href = attributes["href"], let url = URL(string: href, relativeTo: base)?.absoluteURL else { return }
                let rel = attributes["rel"] ?? "", type = attributes["type"] ?? ""
                if entry != nil { entry?.links.append(OPDSEntry.Link(url: url, type: type, rel: rel)) }
                else if rel == "next" { feed.next = url }
                else if rel == "search" {
                    if type.contains("atom") && href.contains("{searchTerms}") { feed.searchTemplate = href }
                    else { feed.searchDescription = url }
                }
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "title": if entry != nil && entry?.title.isEmpty == true { entry?.title = value }
            case "name": if inAuthor, let current = entry?.author { entry?.author = current.isEmpty ? value : current + "、" + value }
            case "author": inAuthor = false
            case "summary", "content": if entry != nil && entry?.summary.isEmpty == true { entry?.summary = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) }
            case "entry": if let entry { feed.entries.append(entry) }; entry = nil
            default: break
            }
        }
    }
}

// MARK: - WiFi 传书

struct WiFiTransferView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var server = WiFiTransferServer()
    @State private var copiedAddress = false
    var body: some View {
        SettingsPage(title: "从电脑传书", detail: "手机与电脑连接同一 Wi-Fi，传书期间请停留在此页（屏幕保持常亮）。") {
            SettingsGroup(title: "无线连接地址", footer: "离开此页后传书服务立即关闭；单次传输文件大小不限。") {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    HStack(spacing: Theme.space3) {
                        ThemeIcon(symbol: Icon.wifi, size: 26).foregroundStyle(Theme.accent)
                        Text(server.address == nil ? "连接同一 Wi-Fi" : "等待电脑连接")
                            .font(.headline).foregroundStyle(Theme.ink)
                    }
                    if let address = server.address {
                        Text("在电脑浏览器打开完整地址（含口令）：").font(.caption).foregroundStyle(Theme.ink2)
                        Text(address)
                            .font(.system(.subheadline, design: .monospaced).weight(.medium))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .foregroundStyle(Theme.ink)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
                        Button {
                            UIPasteboard.general.string = address
                            copiedAddress = true
                            Haptics.light()
                        } label: { Text(copiedAddress ? "地址已复制" : "复制完整地址") }
                        .buttonStyle(SecondaryButtonStyle(emphasized: true))
                        .accessibilityHint("复制后可发送到准备传书的设备")
                    } else if let error = server.error {
                        EditorialNotice(title: "传书服务未能启动", detail: error, kind: .failure)
                        Button("重新连接") { copiedAddress = false; server.stop(); server.start() }
                            .buttonStyle(SecondaryButtonStyle())
                    } else {
                        ProgressView("正在启动传书服务…").font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 6)
            }

            SettingsGroup(title: "本次接收（\(server.received.filter { $0.hasPrefix("✓") }.count) 本）") {
                if server.received.isEmpty {
                    Text("还没有收到文件。在电脑浏览器上传后会自动加入书库。")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(server.received.reversed().enumerated()), id: \.offset) { index, line in
                        HairlineRow(showsDivider: index < server.received.count - 1) {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(line.hasPrefix("✗") ? Theme.danger : Theme.ink)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .navigationTitle("从电脑传书")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Theme.space3) {
                Button("结束传书") { finishTransfer(goToShelf: false) }.buttonStyle(SecondaryButtonStyle())
                Button("返回书库") { finishTransfer(goToShelf: true) }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, Theme.insetCompact).padding(.vertical, Theme.space3)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
            .barMaterialBackground()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            server.onFile = { url in
                do {
                    try await model.importFiles([url])
                    return "✓ " + url.lastPathComponent
                } catch {
                    return "✗ " + url.lastPathComponent + "：" + error.localizedDescription
                }
            }
            server.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            server.stop()
        }
    }

    private func finishTransfer(goToShelf: Bool) {
        server.stop()
        dismiss()
        if goToShelf { model.tab = 0 }
    }
}

/// 极简 HTTP 服务：GET /<口令> 返回上传页；POST /<口令>/upload 以原始请求体接收单个文件（文件名在 X-File-Name 头）。
/// 口令每次开启随机生成并显示在地址里，同一局域网里不知道地址的人无法上传。
@MainActor
final class WiFiTransferServer: ObservableObject {
    @Published private(set) var address: String?
    @Published private(set) var running = false
    @Published private(set) var error: String?
    @Published private(set) var received: [String] = []
    var onFile: ((URL) async -> String)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tingye.wifi-transfer")
    /// 本次服务的访问口令（去掉易混淆字符，便于手输）。
    private(set) var token = ""

    nonisolated static func makeToken(length: Int = 6) -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    func start() {
        guard listener == nil else { return }
        error = nil
        token = Self.makeToken()
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: 8080) ?? .any)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.update(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            // 8080 被占用时让系统分配端口
            if let fallback = try? NWListener(using: .tcp, on: .any) {
                fallback.stateUpdateHandler = { [weak self] state in Task { @MainActor in self?.update(state) } }
                fallback.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
                fallback.start(queue: queue)
                listener = fallback
            } else { self.error = "无法启动传书服务：" + error.localizedDescription }
        }
    }

    func stop() { listener?.cancel(); listener = nil; running = false; address = nil }

    private func update(_ state: NWListener.State) {
        switch state {
        case .ready:
            running = true
            guard let ip = Self.wifiAddress() else { error = "没有连接 WiFi。请连接 WiFi 后重新进入此页。"; address = nil; return }
            address = "http://\(ip):\(listener?.port?.rawValue ?? 8080)/\(token)"
        case .failed(let failure): running = false; error = "传书服务已停止：" + failure.localizedDescription
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        let session = TransferConnection(connection: connection, queue: queue, token: token) { [weak self] url in
            guard let self else { return "" }
            let line = await self.onFile?(url) ?? ""
            self.received.append(line)
            return line
        }
        session.start()
    }

    /// 局域网 IPv4 地址：优先取 en0（WiFi），热点或有线网卡连接时回退到 en* / bridge*
    nonisolated static func wifiAddress() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var primary: String?
        var fallback: String?
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = item.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            guard !ip.isEmpty, !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else { continue }
            if name == "en0" { primary = ip }
            else if fallback == nil { fallback = ip }
        }
        return primary ?? fallback
    }
}

enum TransferRoute: Equatable {
    case page, upload, forbidden

    /// 按去掉查询串与末尾斜杠后的路径分流；口令不符一律拒绝。
    static func resolve(_ path: String, token: String) -> TransferRoute {
        let bare = String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let trimmed = bare.hasSuffix("/") && bare.count > 1 ? String(bare.dropLast()) : bare
        guard !token.isEmpty else { return .forbidden }
        if trimmed == "/" + token { return .page }
        if trimmed == "/" + token + "/upload" { return .upload }
        return .forbidden
    }
}

/// 一个 HTTP 连接：读请求头，GET 返回页面，POST 把请求体流式写入临时文件后交给书库导入。
private final class TransferConnection: @unchecked Sendable {
    let connection: NWConnection
    let queue: DispatchQueue
    let token: String
    let onFile: @MainActor (URL) async -> String
    private var header = Data()
    private var file: FileHandle?
    private var fileURL: URL?
    private var remaining = 0
    private var retain: TransferConnection?

    init(connection: NWConnection, queue: DispatchQueue, token: String, onFile: @escaping @MainActor (URL) async -> String) {
        self.connection = connection; self.queue = queue; self.token = token; self.onFile = onFile
    }


    func start() {
        retain = self
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish() }
            if case .cancelled = state { self?.retain = nil }
        }
        connection.start(queue: queue)
        receiveHeader()
    }

    private func finish() { try? file?.close(); connection.cancel() }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.header.append(data) }
            if let end = self.header.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: self.header[..<end.lowerBound], as: UTF8.self)
                let body = self.header[end.upperBound...]
                self.route(head, body: Data(body))
            } else if complete || error != nil || self.header.count > 64 * 1024 {
                self.finish()
            } else {
                self.receiveHeader()
            }
        }
    }

    private func route(_ head: String, body: Data) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        let method = parts.first.map(String.init) ?? "", path = parts.count > 1 ? String(parts[1]) : "/"
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let route = TransferRoute.resolve(path, token: token)
        if route == .forbidden {
            respond(403, type: "text/plain; charset=utf-8", body: Data("地址不完整。请在浏览器中输入手机传书页上显示的完整地址（含末尾口令）。".utf8))
        } else if method == "GET", route == .page {
            respond(200, type: "text/html; charset=utf-8", body: Data(Self.renderPage(for: AppThemeDirection.current).utf8))
        } else if method == "POST", route == .upload {
            let length = Int(headers["content-length"] ?? "") ?? 0
            let rawName = headers["x-file-name"].flatMap { $0.removingPercentEncoding } ?? "upload.txt"
            let name = (rawName as NSString).lastPathComponent
            guard length > 0 else { respond(422, type: "text/plain; charset=utf-8", body: Data("文件为空".utf8)); return }
            guard ImportableFile.accepts(name) else { respond(415, type: "text/plain; charset=utf-8", body: Data("不支持的格式：\(name)".utf8)); return }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wifi-" + UUID().uuidString)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            fileURL = url; file = try? FileHandle(forWritingTo: url); remaining = length
            write(body)
        } else {
            respond(404, type: "text/plain", body: Data("Not Found".utf8))
        }
    }

    private func write(_ data: Data) {
        let chunk = data.prefix(remaining)
        if !chunk.isEmpty { try? file?.write(contentsOf: chunk); remaining -= chunk.count }
        if remaining <= 0 {
            try? file?.close(); file = nil
            guard let url = fileURL else { return }
            Task { @MainActor in
                let line = await self.onFile(url)
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                let ok = line.hasPrefix("✓")
                self.queue.async { self.respond(ok ? 200 : 422, type: "text/plain; charset=utf-8", body: Data(line.utf8)) }
            }
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.write(data) }
            else if complete || error != nil { self.finish() }
            else { self.write(Data()) }
        }
    }

    private func respond(_ status: Int, type: String, body: Data) {
        let reason = [200: "OK", 403: "Forbidden", 404: "Not Found", 413: "Payload Too Large", 415: "Unsupported Media Type", 422: "Unprocessable"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        if status == 200 && type.hasPrefix("text/html") { head = head.replacingOccurrences(of: "Cache-Control: no-store", with: "Cache-Control: no-cache") }
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { [weak self] _ in self?.connection.cancel() })
    }

    static func renderPage(for direction: AppThemeDirection) -> String {
        let lightVars: String
        let darkVars: String
        let radiusPx: Int
        let btnRadiusPx: Int
        switch direction {
        case .warmPaper:
            lightVars = "--bg:#FAF9F5;--card:#FFFFFF;--ink:#141413;--ink3:#595853;--accent:#A6482B;--clay:#D97757;--on-clay:#141413;--soft:#F8ECE6;--danger:#9E2A2B;--line:#E6E3D9"
            darkVars = "--bg:#141413;--card:#1C1B19;--ink:#FAF9F5;--ink3:#ABA89E;--accent:#ECA085;--clay:#D97757;--on-clay:#141413;--soft:#2E201B;--danger:#F4A6A3;--line:#2E2C29"
            radiusPx = 18; btnRadiusPx = 14
        case .nightInkGold:
            lightVars = "--bg:#F4EFE4;--card:#FFFBF3;--ink:#1A1712;--ink3:#5C564C;--accent:#7A5C16;--clay:#C4A24A;--on-clay:#1A1712;--soft:#F3E6C4;--danger:#9E2A2B;--line:#DDD6C7"
            darkVars = "--bg:#12110E;--card:#1C1A16;--ink:#F3EDE0;--ink3:#A89F8A;--accent:#E8CC7A;--clay:#C4A24A;--on-clay:#12110E;--soft:#2A2418;--danger:#F4A6A3;--line:#3A362E"
            radiusPx = 12; btnRadiusPx = 10
        case .editorial:
            lightVars = "--bg:#F3F0E8;--card:#FFFDF8;--ink:#1C1B19;--ink3:#5A5852;--accent:#8F2D2A;--clay:#8F2D2A;--on-clay:#FFFDF8;--soft:#F3E6E4;--danger:#9E2A2B;--line:#D4D0C6"
            darkVars = "--bg:#141311;--card:#1E1D1A;--ink:#F4F0E6;--ink3:#A8A49A;--accent:#E8A09A;--clay:#C65E58;--on-clay:#141311;--soft:#2E1C1B;--danger:#F4A6A3;--line:#3A3832"
            radiusPx = 4; btnRadiusPx = 3
        case .systemClear:
            lightVars = "--bg:#F2F2F7;--card:#FFFFFF;--ink:#000000;--ink3:#3A3A3C;--accent:#0B63CE;--clay:#0B63CE;--on-clay:#FFFFFF;--soft:#E8F1FC;--danger:#D70015;--line:rgba(60,60,67,.18)"
            darkVars = "--bg:#000000;--card:#1C1C1E;--ink:#FFFFFF;--ink3:#C7C7CC;--accent:#64D2FF;--clay:#0A6CE2;--on-clay:#FFFFFF;--soft:#1A2A3D;--danger:#FF6961;--line:rgba(84,84,88,.45)"
            radiusPx = 12; btnRadiusPx = 10
        }
        let isClear = direction == .systemClear
        let headingFont = isClear
            ? "-apple-system,BlinkMacSystemFont,\"SF Pro Display\",\"PingFang SC\",\"Noto Sans SC\",sans-serif"
            : "\"Noto Serif SC\",\"Songti SC\",\"STSong\",serif"
        let headingWeight = isClear ? "600" : "400"
        let eyebrowStamp = isClear ? "display:none" : "content:\"\";width:8px;height:8px;background:var(--clay);display:inline-block"
        let eyebrowTracking = isClear ? ".02em" : ".14em"
        let eyebrowText = isClear ? "听页 · 无线传书" : "TINGYE · 无线传书"
        return """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>听页 · WiFi 传书</title>
        <style>
        :root{color-scheme:light dark;\(lightVars);--radius:\(radiusPx)px;--btn-radius:\(btnRadiusPx)px}
        @media (prefers-color-scheme:dark){:root{\(darkVars)}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px -apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Noto Sans SC",sans-serif;padding:40px 24px}
        main{max-width:760px;margin:0 auto}
        header{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);padding:24px;margin-bottom:20px}header .intro{color:var(--ink3)}
        .eyebrow{color:var(--accent);font-size:13px;font-weight:600;letter-spacing:\(eyebrowTracking);margin:0 0 10px;display:flex;align-items:center;gap:8px}
        .eyebrow::before{\(eyebrowStamp)}
        h1{font:\(headingWeight) clamp(26px,3.6vw,36px)/1.3 \(headingFont);margin:0 0 8px}
        p{color:var(--ink3);margin:0;line-height:1.6}.intro{margin-bottom:2px}
        .steps{padding:0 0 0 20px;margin:0 0 20px;color:var(--ink3)}.steps li{display:list-item;background:none;border:0;min-height:0;padding:3px 0;margin:0;font-size:14px}.steps li::before{display:none}
        #drop{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);padding:36px 24px;text-align:center;transition:.2s}
        #drop.over{border-color:var(--accent);background:var(--soft)}
        h2{font:\(headingWeight) 22px/1.4 \(headingFont);margin:0 0 8px}.formats{font-size:12px;letter-spacing:.03em}
        button{min-height:46px;background:var(--clay);color:var(--on-clay);border:1px solid transparent;border-radius:var(--btn-radius);padding:11px 24px;font-family:inherit;font-size:15px;font-weight:600;line-height:1.4;cursor:pointer}
        button:focus-visible,#drop:focus-visible{outline:3px solid var(--accent);outline-offset:4px}
        button:disabled{opacity:.45;cursor:default}#choose{min-width:220px;margin-top:16px}
        button.secondary{background:var(--card);color:var(--ink);border:1px solid var(--line);margin:0;min-height:44px}
        .queue-title{font:\(headingWeight) 17px/1.4 \(headingFont);margin:24px 4px 12px}
        ul{list-style:none;padding:0;margin:0}
        #list li{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);padding:14px 16px;margin-bottom:10px;display:flex;align-items:center;gap:20px;min-height:58px;font-size:15px}
        li>div{min-width:0;overflow-wrap:anywhere}li>div:first-of-type{display:grid;grid-template-columns:minmax(0,1.5fr) minmax(100px,1fr);align-items:center;gap:20px}
        .result{flex-basis:18%;max-width:34%;text-align:right;font-size:12px;color:var(--accent)}.result span{display:block;overflow-wrap:anywhere}.result button{margin-top:8px;padding:6px 12px}
        #clear{margin-top:14px}.footnote{font-size:12px;margin-top:20px}
        .ok{color:var(--accent);font-weight:600}.err{color:var(--danger)}.bar{height:4px;background:var(--line);border-radius:2px;overflow:hidden}.bar i{display:block;height:100%;background:var(--clay);width:0}
        @media(prefers-contrast:more){:root{--line:#595853}#drop,#list li{border-width:2px}button:focus-visible{outline-width:4px}}
        @media(prefers-reduced-motion:reduce){*{transition:none!important;scroll-behavior:auto!important}}
        @media(max-width:600px){body{padding:20px 16px}h1{font-size:24px}#drop{padding:24px 16px}#choose{min-width:0;width:100%}#list li{gap:12px;padding:14px 12px}li>div:first-of-type{display:block}.bar{margin-top:10px}.result{flex-basis:30%;max-width:45%}.steps li{padding-right:8px}}
        </style></head><body><main>
        <header><div class="eyebrow">\(eyebrowText)</div><h1>添加书籍到听页</h1><p class="intro">从电脑选择文件，发送后自动加入手机书库。</p></header>
        <ol class="steps" aria-label="传书步骤"><li>手机与电脑连接同一 WiFi</li><li>选择文件，或拖入下方区域</li><li>等待“已加入书架”，再离开手机传书页</li></ol>
        <div id="drop"><h2>拖动书籍到这里</h2><p class="formats">EPUB · TXT · PDF · MOBI · AZW3 · CBZ · CBT · ZIP</p><button type="button" id="choose">选择文件并发送</button><input id="pick" type="file" multiple hidden></div>
        <h3 class="queue-title">传输队列</h3><ul id="list" aria-live="polite" aria-label="传书进度"></ul><button type="button" id="clear" class="secondary" hidden>清除已完成记录</button><p class="footnote">失败文件可单独重试 · 清除记录只移除已完成项<br>也支持 DOCX、Markdown、HTML 和听页备份。文件大小不限。</p></main>
        <script>
        const drop=document.getElementById('drop'),list=document.getElementById('list'),pick=document.getElementById('pick'),clear=document.getElementById('clear');
        const queue=[];let active=false;
        document.getElementById('choose').onclick=()=>pick.click();
        drop.ondragover=e=>{e.preventDefault();drop.classList.add('over')};drop.ondragleave=()=>drop.classList.remove('over');
        drop.ondrop=e=>{e.preventDefault();drop.classList.remove('over');send([...e.dataTransfer.files])};pick.onchange=()=>{send([...pick.files]);pick.value=''};
        clear.onclick=()=>{list.querySelectorAll('li[data-done="true"]').forEach(li=>li.remove());clear.hidden=true};
        function send(files){for(const f of files){const li=document.createElement('li');li.innerHTML='<div style="flex:1"><div></div><div class="bar"><i></i></div></div><div class="result"><span>等待传输</span><button class="secondary" type="button" hidden>重试</button></div>';li.querySelector('div div').textContent=f.name;list.append(li);const retry=li.querySelector('button');retry.onclick=()=>{retry.hidden=true;li.querySelector('span').textContent='等待重试';queue.push([f,li]);drain()};queue.push([f,li])}drain()}
        async function drain(){if(active)return;active=true;while(queue.length){const [f,li]=queue.shift();await up(f,li)}active=false}
        function up(f,li){return new Promise(r=>{const x=new XMLHttpRequest(),status=li.querySelector('span'),retry=li.querySelector('button');status.textContent='传输中';status.className='';li.querySelector('i').style.width='0%';x.open('POST',location.pathname.replace(/\\/$/,'')+'/upload');x.timeout=180000;x.setRequestHeader('X-File-Name',encodeURIComponent(f.name));
        const fail=message=>{status.textContent=message;status.className='err';retry.hidden=false;r()};
        x.upload.onprogress=e=>{if(e.lengthComputable){li.querySelector('i').style.width=(e.loaded/e.total*100)+'%';if(e.loaded===e.total)status.textContent='正在加入书架'}};
        x.onload=()=>{if(x.status===200){status.textContent='已加入书架';status.className='ok';li.dataset.done='true';clear.hidden=false;r()}else fail(x.responseText||'传输失败')};
        x.onerror=()=>fail('连接中断，请确认手机仍在传书页');x.ontimeout=()=>fail('传输超时，请检查手机是否已收到后再重试');x.send(f)})}
        </script></body></html>
        """
    }
}
