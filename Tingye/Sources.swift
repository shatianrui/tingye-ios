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
    static let extensions: Set<String> = ["epub", "txt", "text", "pdf", "html", "htm", "xhtml", "md", "markdown", "docx", "json", "mobi", "azw3", "azw", "cbz", "zip"]
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
        IndexPage {
            fileSection
            if let report = model.importReport {
                NavigationLink { ImportResultsView() } label: {
                    IndexRowLabel(title: Text(report.finished ? "最近导入结果" : "查看导入进度"),
                                  detail: report.indexSummary, symbol: Icon.importFile, disclosure: true)
                        .padding(.horizontal, Theme.space3).indexPanel(fill: IndexTheme.wash)
                }
                .buttonStyle(PressButtonStyle())
            }

            VStack(alignment: .leading, spacing: Theme.space2) {
                IndexHeading(title: Text("无线传输"))
                NavigationLink(value: "wifi-transfer") {
                    IndexRowLabel(title: Text("从电脑传书"), detail: Text("同一 WiFi 下，用浏览器发送文件"),
                                  symbol: Icon.wifi, disclosure: true)
                        .padding(.horizontal, Theme.space3).indexPanel()
                }
                .buttonStyle(PressButtonStyle())
            }

            connectionsSection
            VStack(alignment: .leading, spacing: Theme.space2) {
                IndexHeading(title: Text("连接远程书库"))
                VStack(spacing: 0) {
                    addConnection(.webdav, icon: Icon.server, detail: "坚果云、群晖、Nextcloud 等文件服务器")
                    IndexRule()
                    addConnection(.smb, icon: Icon.server, detail: "局域网 NAS、电脑共享文件夹")
                        .accessibilityIdentifier("sources.addSMB")
                    IndexRule()
                    addConnection(.opds, icon: Icon.catalog, detail: "Calibre-Web、Talebook 等书目服务")
                }
                .padding(.horizontal, Theme.space3)
                .indexPanel()
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
    private var fileSection: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            IndexHeading(title: Text("从文件导入"), detail: Text("本机、iCloud 云盘或已连接的网盘"), large: true)
            VStack(spacing: Theme.space2) {
                // 根宿主在本面板实际关闭后消费请求。
                Button("选择文件") { model.requestFileImport(); dismiss() }
                    .buttonStyle(IndexActionStyle(role: .primary, expands: true))
                    .accessibilityIdentifier("sources.importFile")
                Button("批量导入文件") { model.requestFileImport(multiple: true); dismiss() }
                    .buttonStyle(IndexActionStyle(role: .secondary, expands: true))
                    .accessibilityIdentifier("sources.importBatch")
            }
            .disabled(model.busy)
            Text("支持 EPUB、TXT、MOBI、AZW3、PDF、DOCX、Markdown、CBZ 等格式。")
                .font(.caption).foregroundStyle(IndexTheme.muted)
        }
        .padding(Theme.space4)
        .indexPanel()
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            IndexHeading(title: Text("已保存的连接"))
            if sources.isEmpty {
                IndexStatus(kind: .empty, title: Text("还没有书库连接"),
                            detail: Text("选择下方的协议，添加你自己的书库。"))
            } else {
                VStack(spacing: 0) {
                    ForEach(sources) { source in
                        connectionRow(source)
                        if source.id != sources.last?.id { IndexRule() }
                    }
                }
                .padding(.horizontal, Theme.space3)
                .indexPanel()
                Text("连接只保存在这台设备。移除连接不会删除服务器文件或已导入的书籍。")
                    .font(.caption).foregroundStyle(IndexTheme.muted)
            }
        }
    }

    private func addConnection(_ kind: RemoteSource.Kind, icon: String, detail: LocalizedStringKey) -> some View {
        Button {
            editing = RemoteSource(kind: kind, name: "", url: kind == .smb ? "smb://" : "https://")
        } label: {
            IndexRowLabel(title: Text(verbatim: kind.rawValue.uppercased()), detail: Text(detail),
                          symbol: icon, disclosure: true)
        }
        .buttonStyle(PressButtonStyle())
    }

    private func connectionRow(_ source: RemoteSource) -> some View {
        let location = [source.kind.rawValue.uppercased(), source.baseURL?.host()].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: Theme.space2) {
            NavigationLink {
                switch source.kind {
                case .webdav: WebDAVBrowser(source: source, path: "")
                case .smb: SMBBrowser(source: source, share: nil, path: "")
                case .opds: OPDSBrowser(source: source, url: source.baseURL, title: source.name)
                }
            } label: {
                IndexRowLabel(title: Text(verbatim: source.name), detail: Text(verbatim: location),
                              symbol: source.kind == .opds ? Icon.catalog : Icon.server, disclosure: true)
            }
            .buttonStyle(PressButtonStyle())
            Menu { connectionActions(source) } label: {
                ThemeIcon(symbol: Icon.more, size: 20).foregroundStyle(IndexTheme.accent)
                    .frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize).contentShape(Rectangle())
            }
            .accessibilityLabel("管理书库：\(source.name)")
        }
        .contextMenu { connectionActions(source) }
    }

    @ViewBuilder private func connectionActions(_ source: RemoteSource) -> some View {
        Button { editing = source } label: { Label("编辑连接", systemImage: Icon.edit) }
        Button(role: .destructive) { removing = source } label: { Label("移除连接", systemImage: Icon.delete) }
    }

    private func remove(_ source: RemoteSource) {
        sources.removeAll { $0.id == source.id }
        SourceStore.setPassword("", for: source.id)
        SourceStore.save(sources)
    }
}

/// 导入面板：书库页头「＋」打开，本机文件、电脑传书与远程书库收进同一个 sheet。
struct ImportHubView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SourcesView()
                .navigationTitle("添加书籍")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }.font(.subheadline.weight(.semibold))
                }
            }
        }
        .tint(IndexTheme.accent)
        .feedbackOverlay()
        .respectReducedMotion()
    }
}

private struct SourceEditor: View {
    private enum Field: Hashable { case name, address, username, password }

    @State var source: RemoteSource
    let onSave: (RemoteSource, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focus: Field?
    @State private var password = ""
    private var validAddress: Bool {
        if source.kind == .smb { return SMBAccess.target(source.url) != nil }
        return ["http", "https"].contains(source.baseURL?.scheme?.lowercased() ?? "") && source.baseURL?.host() != nil
    }
    private var addressLabel: LocalizedStringKey { source.kind == .opds ? "书目地址" : "服务器地址" }

    var body: some View {
        NavigationStack {
            IndexPage {
                connectionFields
                accessFields
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { editorActions }
            .tint(IndexTheme.accent)
            .onAppear { password = source.password }
        }
    }

    private var navigationTitle: LocalizedStringKey {
        switch source.kind {
        case .webdav: "连接 WebDAV"
        case .smb: "连接 SMB"
        case .opds: "连接 OPDS"
        }
    }

    private var connectionFields: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            IndexHeading(title: Text("书库信息"))
            field("名称", slot: .name) {
                TextField("为书库取一个名字", text: $source.name)
                    .submitLabel(.next).onSubmit { focus = .address }
            }
            field(addressLabel, slot: .address) {
                TextField(source.kind == .smb ? "smb://192.168.1.10" : "https://", text: $source.url)
                    .keyboardType(.URL).textContentType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.next).onSubmit { focus = .username }
            }
            if !validAddress && source.url.count > 8 {
                IndexStatus(kind: .failure, title: Text("请检查服务器地址"),
                            detail: Text(source.kind == .smb ? "使用 smb:// 加 NAS 或电脑地址。" : "使用完整的 http:// 或 https:// 地址。"))
            }
        }
        .padding(Theme.space4)
        .indexPanel()
    }

    private var accessFields: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            IndexHeading(title: Text("访问凭据 · 选填"))
            field("用户名", slot: .username) {
                TextField("选填", text: $source.username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.next).onSubmit { focus = .password }
            }
            field("密码 / 应用密码", slot: .password) {
                SecureField("选填", text: $password)
                    .textContentType(.password).privacySensitive()
                    .submitLabel(.done).onSubmit { focus = nil }
            }
            accessGuidance.font(.caption).foregroundStyle(IndexTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.space4)
        .indexPanel()
    }

    private var accessGuidance: Text {
        switch source.kind {
        case .smb: Text("填写 smb:// 加 NAS 或电脑的局域网地址，共享文件夹在连接后选择。不填用户名则以访客登录。")
        case .webdav: Text("填写完整的 http:// 或 https:// 地址。坚果云请使用第三方应用管理中生成的应用密码。")
        case .opds: Text("填写完整的 http:// 或 https:// 书目地址。多数 OPDS 服务无需登录，开启登录的书库请填写账号。")
        }
    }

    private var editorActions: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.space1))
            : AnyLayout(HStackLayout(spacing: Theme.space3))
        return VStack(spacing: 0) {
            IndexRule()
            layout {
                Button("取消") { dismiss() }.buttonStyle(IndexActionStyle(role: .plain, expands: true))
                Button("保存连接") {
                    if source.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        source.name = SMBAccess.target(source.url)?.host ?? source.baseURL?.host() ?? source.kind.rawValue.uppercased()
                    }
                    onSave(source, password)
                    dismiss()
                }
                .buttonStyle(IndexActionStyle(role: .primary, expands: true))
                .disabled(!validAddress)
            }
            .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space2)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .background(IndexTheme.canvas)
    }

    private func field<Content: View>(_ title: LocalizedStringKey, slot: Field, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.space1) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(IndexTheme.ink)
                .accessibilityHidden(true)
            content().font(.body).foregroundStyle(IndexTheme.ink)
                .focused($focus, equals: slot)
                .accessibilityLabel(Text(title))
                .padding(.horizontal, Theme.space3).frame(minHeight: Theme.rowMinHeight)
                .background(IndexTheme.canvas, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: IndexTheme.controlRadius)
                        .strokeBorder(focus == slot ? IndexTheme.accent : IndexTheme.edge,
                                      lineWidth: focus == slot ? Theme.ruleMedium : Theme.rule)
                        .allowsHitTesting(false)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Stable presentation for directory failures. Third-party errors can include the full source URL.
struct SourceBrowseFailure {
    let detail: Text

    init(_ error: Error, localNetwork: Bool = false) {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                detail = Text("网络不可用。检查网络后重试。")
                return
            case .userAuthenticationRequired:
                detail = Text("需要登录，请返回连接设置检查访问凭据。")
                return
            case .cancelled, .userCancelledAuthentication:
                detail = Text("请求已取消。可以重新加载。")
                return
            default: break
            }
        }
        if !localNetwork, let known = error as? ReaderError {
            detail = Text(L(known.localizedDescription))
        } else if localNetwork {
            detail = Text("请检查共享地址、登录信息与系统的本地网络权限。")
        } else {
            detail = Text("检查网络、服务器地址与登录信息后重试。")
        }
    }
}

struct SourceFileRow: View {
    let name: String
    let isFolder: Bool
    let size: String?

    var body: some View {
        IndexRowLabel(title: Text(verbatim: name), detail: metadata,
                      symbol: isFolder ? Icon.folder : Icon.document)
    }

    private var metadata: Text {
        if isFolder { return Text("文件夹") }
        let action = Text(ImportableFile.accepts(name) ? "导入" : "不支持此格式")
        if let size { return Text("\(size) · \(action)") }
        return action
    }
}

struct WebDAVBrowser: View {
    let source: RemoteSource
    let path: String
    @EnvironmentObject var model: AppModel
    @State private var items: [WebDAVItem] = []
    @State private var loading = true
    @State private var error: SourceBrowseFailure?
    @State private var query = ""
    private var shown: [WebDAVItem] { query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            IndexHeading(title: Text(verbatim: path.isEmpty ? source.name : path.removingPercentEncoding ?? path),
                         detail: Text("浏览文件夹，选择书籍后下载到本机。"))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            if loading {
                IndexStatus(kind: .loading, title: Text("正在读取文件夹…"))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if let error {
                Section {
                    IndexStatus(kind: .failure, title: Text("连接暂时未完成"), detail: error.detail)
                    Button("重新加载") { Task { await load() } }
                        .buttonStyle(IndexActionStyle(role: .secondary))
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if shown.isEmpty {
                IndexStatus(kind: .empty, title: Text(query.isEmpty ? "空文件夹" : "未找到匹配文件"))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(shown) { item in
                if item.isFolder {
                    NavigationLink { WebDAVBrowser(source: source, path: item.path) } label: { row(item) }
                } else if ImportableFile.accepts(item.name) {
                    Button { download(item) } label: { row(item) }
                        .buttonStyle(PressButtonStyle())
                        .disabled(model.busy)
                } else {
                    row(item)
                }
            }
            .listRowBackground(IndexTheme.surface)
        }
        .indexList()
        .navigationTitle(path.isEmpty ? source.name : (path as NSString).lastPathComponent.removingPercentEncoding ?? path)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, prompt: "在当前文件夹中搜索")
        .refreshable { await load() }
        .task { await load() }
    }

    private func row(_ item: WebDAVItem) -> some View {
        SourceFileRow(name: item.name, isFolder: item.isFolder,
                      size: item.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { items = try await WebDAV.list(source, path: path); error = nil }
        catch { self.error = SourceBrowseFailure(error) }
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
    @State private var error: SourceBrowseFailure?
    @State private var searchText = ""
    @State private var remoteSearchTemplate: String?
    @State private var showingSearchResults = false
    @State private var loadedURL: URL?
    @State private var lastAttemptURL: URL?
    @State private var lastAttemptWasSearch = false
    private var shownEntries: [OPDSEntry] {
        (feed?.entries ?? []).filter {
            searchText.isEmpty || remoteSearchTemplate != nil || ($0.title + $0.author).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            IndexHeading(title: Text(verbatim: title),
                         detail: Text(remoteSearchTemplate == nil ? "可以筛选当前书目。" : "输入关键词后提交，搜索远程书目。"))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            if loading {
                IndexStatus(kind: .loading, title: Text("正在读取书目…"))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if let error {
                Section {
                    IndexStatus(kind: .failure, title: Text("连接暂时未完成"), detail: error.detail)
                    Button("重试此请求") { Task { await load(lastAttemptURL ?? url, searchResults: lastAttemptWasSearch) } }
                        .buttonStyle(IndexActionStyle(role: .secondary))
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if shownEntries.isEmpty {
                IndexStatus(kind: .empty, title: Text(searchText.isEmpty ? "这里还没有书目" : "未找到匹配书目"),
                            detail: Text("可以返回分类，或下拉重新加载。"))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if showingSearchResults {
                Button("返回全部书目") { searchText = ""; Task { await load(url) } }
                    .buttonStyle(IndexActionStyle(role: .secondary)).disabled(loading)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(shownEntries) { entry in
                if let acquisition = entry.acquisition {
                    Button { model.importRemote(acquisition.url, name: entry.title + "." + acquisition.fileExtension, source: source) } label: {
                        bookRow(entry, acquisition)
                    }
                    .buttonStyle(PressButtonStyle())
                    .disabled(model.busy)
                } else if let next = entry.navigation {
                    NavigationLink { OPDSBrowser(source: source, url: next, title: entry.title) } label: {
                        IndexRowLabel(title: Text(verbatim: entry.title),
                                      detail: entry.summary.isEmpty ? Text("浏览书目") : Text(verbatim: entry.summary),
                                      symbol: Icon.folder)
                    }
                }
            }
            .listRowBackground(IndexTheme.surface)
            if let next = feed?.next {
                NavigationLink { OPDSBrowser(source: source, url: next, title: title) } label: {
                    IndexRowLabel(title: Text("下一页"), symbol: Icon.nextDirection)
                }
                .listRowBackground(IndexTheme.surface)
            }
        }
        .indexList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.visible, for: .navigationBar)
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
        let format = acquisition.fileExtension.uppercased()
        return HStack(spacing: Theme.space3) {
            AsyncImage(url: entry.thumbnail) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                CoverView(title: entry.title, color: "gray", width: 44, usesIndexPalette: true)
            }
            .frame(width: 44, height: 59)
            .clipShape(RoundedRectangle(cornerRadius: IndexTheme.coverRadius))
            .accessibilityHidden(true)
            IndexRowLabel(title: Text(verbatim: entry.title),
                          detail: Text("\(entry.author.isEmpty ? format : entry.author + " · " + format) · 导入"),
                          symbol: nil)
        }
    }

    private func load(_ target: URL?, searchResults: Bool = false) async {
        guard let target else { error = SourceBrowseFailure(ReaderError.message("OPDS 地址无效。")); loading = false; return }
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
        } catch { self.error = SourceBrowseFailure(error) }
    }
}

struct OPDSEntry: Identifiable, Sendable {
    struct Link: Sendable { let url: URL; let type: String; let rel: String
        var fileExtension: String {
            let map = ["application/epub+zip": "epub", "application/pdf": "pdf", "text/plain": "txt", "application/x-mobipocket-ebook": "mobi",
                       "application/vnd.amazon.ebook": "azw3", "application/x-mobi8-ebook": "azw3", "application/vnd.comicbook+zip": "cbz", "application/x-cbz": "cbz", "application/zip": "zip"]
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        IndexPage {
            IndexHeading(title: Text("从电脑传书"), detail: Text("手机与电脑连接同一 WiFi，保持此页开启。"), large: true)
            connectionPanel
            receivedFiles
            Text("传书时请停留在此页，屏幕会保持常亮。离开后服务立即关闭；文件大小不限。")
                .font(.caption).foregroundStyle(IndexTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("从电脑传书")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { transferActions }
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

    @ViewBuilder private var connectionPanel: some View {
        if let error = server.error {
            VStack(alignment: .leading, spacing: Theme.space2) {
                IndexStatus(kind: .failure, title: Text("传书服务未能启动"), detail: Text(L(error)))
                Text("请检查 WiFi 和系统的本地网络权限。").font(.subheadline).foregroundStyle(IndexTheme.muted)
                Button("重新连接") { copiedAddress = false; server.stop(); server.start() }
                    .buttonStyle(IndexActionStyle(role: .secondary))
            }
        } else if let address = server.address {
            VStack(alignment: .leading, spacing: Theme.space2) {
                IndexHeading(title: Text("等待电脑连接"), detail: Text("在电脑浏览器打开"))
                Text(verbatim: address).font(.body.monospaced()).foregroundStyle(IndexTheme.ink)
                    .textSelection(.enabled).privacySensitive()
                    .fixedSize(horizontal: false, vertical: true)
                Text("完整链接包含本次传书凭证").font(.caption).foregroundStyle(IndexTheme.muted)
                Button {
                    UIPasteboard.general.string = address
                    copiedAddress = true
                    Haptics.light()
                } label: { IndexActionLabel(title: copiedAddress ? "地址已复制" : "复制完整地址", symbol: Icon.copy) }
                .buttonStyle(IndexActionStyle(role: .primary, expands: true))
                .accessibilityHint("复制后可发送到准备传书的设备")
            }
            .padding(Theme.space4)
            .indexPanel()
        } else {
            IndexStatus(kind: .loading, title: Text("正在启动传书服务…"))
        }
    }

    private var receivedFiles: some View {
        let importedCount = server.received.filter { $0.hasPrefix("✓") }.count
        return VStack(alignment: .leading, spacing: Theme.space2) {
            IndexHeading(title: Text("本次接收"), detail: Text("已导入 \(importedCount) 本"))
            if server.received.isEmpty {
                IndexStatus(kind: .empty, title: Text("还没有收到文件"),
                            detail: Text("在电脑上选择文件，接收后会自动加入书库。"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(server.received.reversed().enumerated()), id: \.offset) { index, line in
                        if index > 0 { IndexRule() }
                        let success = line.hasPrefix("✓")
                        IndexRowLabel(title: Text(verbatim: String(line.dropFirst(2))),
                                      detail: Text(success ? "已加入书库" : "导入失败"),
                                      symbol: success ? Icon.markRead : Icon.warning)
                    }
                }
                .padding(.horizontal, Theme.space3)
                .indexPanel()
            }
        }
    }

    private var transferActions: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.space1))
            : AnyLayout(HStackLayout(spacing: Theme.space3))
        return VStack(spacing: 0) {
            IndexRule()
            layout {
                Button("返回书库") { finishTransfer(goToShelf: true) }
                    .buttonStyle(IndexActionStyle(role: .plain, expands: true))
                Button("结束传书") { finishTransfer(goToShelf: false) }
                    .buttonStyle(IndexActionStyle(role: .secondary, expands: true))
            }
            .padding(.horizontal, Theme.space4).padding(.vertical, Theme.space2)
            .frame(maxWidth: Theme.pageWidth).frame(maxWidth: .infinity)
        }
        .background(IndexTheme.canvas)
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
            respond(200, type: "text/html; charset=utf-8", body: Data(Self.page.utf8))
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

    static let page = """
    <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>听页 · WiFi 传书</title>
    <style>
    :root{--bg:#F4F6F8;--card:#FFFFFF;--ink:#12161C;--ink3:#465264;--accent:#163E73;--soft:#E3EDF8;--danger:#9B2C3C;--line:#C3CCD6}
    @media (prefers-color-scheme:dark){:root{--bg:#0E1216;--card:#171C22;--ink:#F3F6F9;--ink3:#B4C0CE;--accent:#A9C9F2;--soft:#1A2C44;--danger:#F5B3BC;--line:#3A4450}button{background:#A9C9F2;color:#0E1622;border-color:#A9C9F2}li::before{filter:brightness(0) invert(.9)}}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px "Noto Sans SC",-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;padding:48px}
    main{max-width:1286px;margin:0 auto}.eyebrow{color:var(--accent);font-size:12px;margin:0 0 24px}h1{font:400 36px/1.5 "Noto Serif SC","Songti SC","STSong",serif;margin:0 0 20px}p{color:var(--ink3);margin:0;line-height:1.7}.intro{margin-bottom:26px}
    #drop{background:var(--card);border:1px solid transparent;border-radius:16px;padding:32px;text-align:center;transition:.2s}#drop.over{border-color:var(--accent);background:var(--soft)}.asset{display:block;width:24px;height:24px;margin:0 auto 20px;background:var(--accent);-webkit-mask:url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiMyNDIxMUYiIHN0cm9rZS13aWR0aD0iMS43IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxwYXRoIGQ9Ik0xMiAxNVYzIi8+PHBhdGggZD0iTTIxIDE1djRhMiAyIDAgMCAxLTIgMkg1YTIgMiAwIDAgMS0yLTJ2LTQiLz48cGF0aCBkPSJtNyAxMCA1IDUgNS01Ii8+PC9zdmc+) center/contain no-repeat;mask:url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiMyNDIxMUYiIHN0cm9rZS13aWR0aD0iMS43IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxwYXRoIGQ9Ik0xMiAxNVYzIi8+PHBhdGggZD0iTTIxIDE1djRhMiAyIDAgMCAxLTIgMkg1YTIgMiAwIDAgMS0yLTJ2LTQiLz48cGF0aCBkPSJtNyAxMCA1IDUgNS01Ii8+PC9zdmc+) center/contain no-repeat}h2{font:400 26px/1.5 "Noto Serif SC","Songti SC","STSong",serif;margin:0 0 14px}.formats{font-size:12px}
    button{min-height:48px;background:#163E73;color:#FFFFFF;border:1px solid #163E73;border-radius:12px;padding:12px 24px;font-family:inherit;font-size:15px;font-weight:600;line-height:1.4;cursor:pointer}button:focus-visible,#drop:focus-visible{outline:3px solid var(--accent);outline-offset:4px}button:disabled{opacity:.45;cursor:default}#choose{min-width:240px;margin-top:18px}button.secondary{background:var(--card);color:var(--ink);border:1px solid var(--line);margin:0;min-height:44px}
    .queue-title{font-size:18px;font-weight:500;margin:26px 0 18px}ul{list-style:none;padding:0;margin:0}li{background:var(--card);border-radius:12px;padding:16px;margin-bottom:16px;display:flex;align-items:center;gap:24px;min-height:64px;font-size:15px}li::before{content:"";flex:none;display:block;width:24px;height:24px;background:center/contain no-repeat url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiMyNDIxMUYiIHN0cm9rZS13aWR0aD0iMS43IiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxwYXRoIGQ9Ik02IDIyYTIgMiAwIDAgMS0yLTJWNGEyIDIgMCAwIDEgMi0yaDhhMi40IDIuNCAwIDAgMSAxLjcwNC43MDZsMy41ODggMy41ODhBMi40IDIuNCAwIDAgMSAyMCA4djEyYTIgMiAwIDAgMS0yIDJ6Ii8+PHBhdGggZD0iTTE0IDJ2NWExIDEgMCAwIDAgMSAxaDUiLz48L3N2Zz4=)}
    li>div{min-width:0;overflow-wrap:anywhere}li>div:first-of-type{display:grid;grid-template-columns:minmax(0,1.5fr) minmax(100px,1fr);align-items:center;gap:24px}.result{flex-basis:18%;max-width:34%;text-align:right;font-size:12px;color:var(--accent)}.result span{display:block;overflow-wrap:anywhere}.result button{margin-top:8px;padding:6px 12px}#clear{margin-top:16px}.footnote{font-size:12px;margin-top:24px}
    .ok{color:var(--accent)}.err{color:var(--danger)}.bar{height:4px;background:var(--line);border-radius:2px;overflow:hidden}.bar i{display:block;height:100%;background:var(--accent);width:0}
    @media(max-width:600px){body{padding:28px 20px}h1{font-size:28px}#drop{padding:28px 16px}#choose{min-width:0;width:100%}li{gap:12px;padding:16px 12px}li>div:first-of-type{display:block}.bar{margin-top:10px}.result{flex-basis:30%;max-width:38%}}
    header{border-bottom:1px solid var(--line);margin-bottom:24px}body{font-size:16px;background:var(--bg)}main{max-width:1000px}h1{font-size:clamp(30px,4vw,48px);line-height:1.35}.eyebrow{font-weight:600;letter-spacing:.08em}.steps{padding:0 0 0 24px;margin:0 0 32px;color:var(--ink3)}.steps li{display:list-item;background:none;min-height:0;padding:4px 0;margin:0;font-size:15px}.steps li::before{display:none}#drop{border:1px solid var(--line);border-radius:12px;padding:40px 24px}button{border-radius:10px;background:var(--accent);border-color:var(--accent)}#list li{border:1px solid var(--line);border-radius:10px}.queue-title{border-bottom:1px solid var(--line);padding-bottom:12px}
    :root{--bg:#F4F6F8;--card:#FFFFFF;--ink:#12161C;--ink3:#465264;--accent:#163E73;--soft:#E3EDF8;--danger:#9B2C3C;--line:#C3CCD6}
    @media(prefers-color-scheme:dark){:root{--bg:#0E1216;--card:#171C22;--ink:#F3F6F9;--ink3:#B4C0CE;--accent:#A9C9F2;--soft:#1A2C44;--danger:#F5B3BC;--line:#3A4450}button{background:var(--accent);border-color:var(--accent);color:#0E1622}}
    @media(prefers-contrast:more){:root{--line:#80776B}#drop,#list li{border-width:2px}button:focus-visible{outline-width:4px}}
    @media(prefers-reduced-motion:reduce){*{transition:none!important;scroll-behavior:auto!important}}
    @media(max-width:600px){li>div:first-of-type{display:block}.result{max-width:45%}.steps li{padding-right:8px}}
    </style></head><body><main>
    <header><div class="eyebrow">听页 · 私人书库</div><h1>把想读的书，带到身边。</h1><p class="intro">从电脑选书，回到手机开始阅读。</p></header>
    <ol class="steps" aria-label="传书步骤"><li>手机与电脑连接同一 WiFi</li><li>选择文件，或拖入下方区域</li><li>等待“已加入书架”，再离开手机传书页</li></ol>
    <div id="drop"><span class="asset" aria-hidden="true"></span><h2>拖动书籍到这里</h2><p class="formats">EPUB · TXT · PDF · MOBI · AZW3 · CBZ · ZIP</p><button type="button" id="choose">选择文件并发送</button><input id="pick" type="file" multiple hidden></div>
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
