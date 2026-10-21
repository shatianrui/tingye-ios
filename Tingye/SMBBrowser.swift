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

struct SMBBrowser: View {
    let source: RemoteSource
    /// nil 表示列出全部共享。
    let share: String?
    let path: String
    @EnvironmentObject var model: AppModel
    @State private var shares: [String] = []
    @State private var files: [SMBEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    private var shownFiles: [SMBEntry] { query.isEmpty ? files : files.filter { $0.name.localizedCaseInsensitiveContains(query) } }

    struct SMBEntry: Identifiable, Hashable { let name: String; let isFolder: Bool; let size: UInt64; var id: String { name } }

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
                    NavigationLink { SMBBrowser(source: source, share: name, path: "") } label: {
                        Label(name, systemImage: Icon.folderFill).foregroundStyle(Theme.ink)
                    }
                }
                .listRowBackground(Theme.surface)
            } else {
                ForEach(shownFiles) { item in
                    if item.isFolder {
                        NavigationLink { SMBBrowser(source: source, share: share, path: join(item.name)) } label: { row(item) }
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
            let client = try await SMBAccess.client(source)
            if let share {
                try await client.connectShare(share)
                files = try await client.listDirectory(path: path)
                    .filter { !$0.isHidden && $0.name != "." && $0.name != ".." }
                    .map { SMBEntry(name: $0.name, isFolder: $0.isDirectory, size: $0.size) }
                    .sorted { $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                try? await client.disconnectShare()
            } else {
                shares = try await client.listShares()
                    .filter { $0.type.contains(.diskTree) && !$0.type.contains(.special) && !$0.name.hasSuffix("$") }
                    .map(\.name)
            }
            try? await client.logoff()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func download(_ item: SMBEntry) {
        guard let share else { return }
        let remote = join(item.name), source = source
        guard item.size <= 100 * 1024 * 1024 else { model.message = "文件超过 100 MB，无法导入。"; return }
        model.run("正在下载《\((item.name as NSString).deletingPathExtension)》") { [model] in
            let client = try await SMBAccess.client(source)
            try await client.connectShare(share)
            let data = try await client.download(path: remote)
            try? await client.disconnectShare(); try? await client.logoff()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("smb-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let target = folder.appendingPathComponent((item.name as NSString).lastPathComponent)
            try data.write(to: target)
            try await model.importWithFeedback([target])
        }
    }
}
