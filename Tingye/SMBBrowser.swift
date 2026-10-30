import SwiftUI
import SMBClient

/// 内置 SMB：直接浏览局域网 NAS / 共享文件夹并导入书籍（不经过「文件」App）。
/// 地址写作 `smb://主机[:端口]`；共享与目录在浏览时选择。凭据与 WebDAV 一样存钥匙串。
enum SMBAccess {
    struct Target: Equatable { let host: String; let port: Int }
    static func target(_ address: String) -> Target? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text.contains("://") ? text : "smb://" + text),
              url.scheme?.lowercased() == "smb", let host = url.host(), !host.isEmpty else { return nil }
        return Target(host: host, port: url.port ?? 445)
    }
    /// 建立连接并登录；未填用户名时以访客身份登录。
    static func client(_ source: RemoteSource) async throws -> SMBClient {
        guard let target = target(source.url) else { throw ReaderError.message("SMB 地址无效，请填写 smb://主机地址。") }
        let client = SMBClient(host: target.host, port: target.port)
        do {
            let user = source.username.trimmingCharacters(in: .whitespaces)
            try await client.login(username: user.isEmpty ? "guest" : user, password: user.isEmpty ? "" : source.password)
        } catch {
            throw ReaderError.message("无法登录 SMB 服务器：\(error.localizedDescription)。请检查地址、账号与密码，并确认设备在同一局域网。")
        }
        return client
    }
}

/// 一次浏览共用的 SMB 会话：首次使用时登录，之后逐层进入文件夹不再重复登录；
/// 操作串行执行（共享连接是会话级状态），任何一步出错都登出作废，下次重新登录。浏览页全部退出后登出。
@MainActor
final class SMBConnection: ObservableObject {
    let source: RemoteSource
    private var client: SMBClient?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(source: RemoteSource) { self.source = source }

    deinit {
        if let client { Task { _ = try? await client.logoff() } }
    }

    /// 在已登录的会话上执行；给了 share 时先连接共享，结束后断开。
    func perform<T>(share: String? = nil, _ body: (SMBClient) async throws -> T) async throws -> T {
        await acquire(); defer { release() }
        do {
            let client: SMBClient
            if let existing = self.client { client = existing } else { client = try await SMBAccess.client(source); self.client = client }
            guard let share else { return try await body(client) }
            _ = try await client.connectShare(share)
            let result = try await body(client)
            _ = try? await client.disconnectShare()
            return result
        } catch {
            await invalidate()
            throw error
        }
    }

    private func invalidate() async {
        guard let client else { return }
        self.client = nil
        _ = try? await client.logoff()
    }

    private func acquire() async {
        if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

struct SMBBrowser: View {
    let source: RemoteSource
    /// nil 表示列出全部共享。
    let share: String?
    let path: String
    @StateObject private var connection: SMBConnection
    @EnvironmentObject var model: AppModel
    @State private var shares: [String] = []
    @State private var files: [SMBEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    private var shownFiles: [SMBEntry] { query.isEmpty ? files : files.filter { $0.name.localizedCaseInsensitiveContains(query) } }

    struct SMBEntry: Identifiable, Hashable { let name: String; let isFolder: Bool; let size: UInt64; var id: String { name } }

    /// 根页面新建会话，子文件夹沿用上层的 `connection`。
    init(source: RemoteSource, share: String?, path: String, connection: SMBConnection? = nil) {
        self.source = source; self.share = share; self.path = path
        _connection = StateObject(wrappedValue: connection ?? SMBConnection(source: source))
    }

    var body: some View {
        List {
            if let error {
                Section {
                    Label(error, systemImage: Icon.warning).foregroundStyle(Theme.danger)
                    Button("重新加载") { Task { await load() } }.disabled(loading)
                }
            }
            if share == nil {
                ForEach(shares, id: \.self) { name in
                    NavigationLink { SMBBrowser(source: source, share: name, path: "", connection: connection) } label: {
                        Label(name, systemImage: Icon.folderFill).foregroundStyle(Theme.ink)
                    }
                }
                .listRowBackground(Theme.surface)
            } else {
                ForEach(shownFiles) { item in
                    if item.isFolder {
                        NavigationLink { SMBBrowser(source: source, share: share, path: join(item.name), connection: connection) } label: { row(item) }
                    } else {
                        Button { download(item) } label: { row(item) }
                            .disabled(!ImportableFile.accepts(item.name) || model.busy)
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if error == nil && (share == nil ? shares.isEmpty : shownFiles.isEmpty) {
                ContentUnavailableView(share == nil ? "没有可用的共享" : (query.isEmpty ? "空文件夹" : "未找到匹配文件"), systemImage: Icon.folder)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(share == nil ? source.name : (path.isEmpty ? share! : (path as NSString).lastPathComponent))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $query, prompt: "在当前文件夹中搜索")
        .refreshable { await load() }
        .task { await load() }
    }

    private func join(_ name: String) -> String { path.isEmpty ? name : path + "/" + name }

    private func row(_ item: SMBEntry) -> some View {
        let importable = ImportableFile.accepts(item.name)
        return HStack(spacing: 14) {
            ThemeIcon(symbol: item.isFolder ? Icon.folder : importable ? Icon.read : Icon.document, size: 24)
                .foregroundStyle(item.isFolder ? Theme.accent : importable ? Theme.ink2 : Theme.ink3)
                .frame(width: 24, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.subheadline.weight(.medium)).foregroundStyle(item.isFolder || importable ? Theme.ink : Theme.ink3).lineLimit(2)
                if !item.isFolder { Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)).font(.caption).foregroundStyle(Theme.ink3) }
            }
            Spacer()
            if !item.isFolder && importable { Label("导入", systemImage: Icon.downloadFile).font(.caption.weight(.medium)).foregroundStyle(Theme.accent) }
        }
        .padding(.vertical, 6).contentShape(Rectangle())
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            if let share {
                let path = path
                files = try await connection.perform(share: share) { client in
                    try await client.listDirectory(path: path)
                        .filter { !$0.isHidden && $0.name != "." && $0.name != ".." }
                        .map { SMBEntry(name: $0.name, isFolder: $0.isDirectory, size: $0.size) }
                        .sorted { $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
            } else {
                shares = try await connection.perform { client in
                    try await client.listShares()
                        .filter { $0.type.contains(.diskTree) && !$0.type.contains(.special) && !$0.name.hasSuffix("$") }
                        .map(\.name)
                }
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func download(_ item: SMBEntry) {
        guard let share else { return }
        let remote = join(item.name)
        model.run("正在下载《\((item.name as NSString).deletingPathExtension)》") { [model, connection] in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("smb-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let target = folder.appendingPathComponent((item.name as NSString).lastPathComponent)
            // 直接流式写入临时文件，不把整本书读进内存。
            try await connection.perform(share: share) { client in try await client.download(path: remote, localPath: target) }
            try await model.importWithFeedback([target])
        }
    }
}
