import SwiftUI

/// 空间整理：分项统计书库、语音缓存、封面索引与临时文件的占用，并可分别清理；附书库索引修复。
struct StorageView: View {
    @EnvironmentObject var model: AppModel
    @State private var usage: [StorageUsage.Item] = []
    @State private var scanning = false
    @State private var confirmAll = false

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(StorageUsage.format(usage.reduce(0) { $0 + $1.bytes }))
                        .font(Theme.serifBold(34, relativeTo: .largeTitle)).monospacedDigit()
                    Spacer()
                    if scanning { ProgressView() }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("听页共占用 " + StorageUsage.format(usage.reduce(0) { $0 + $1.bytes }))
            } header: { Text("总占用") }
            .listRowBackground(Theme.surface)

            Section {
                ForEach(usage) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.kind.title)
                            Text(item.kind.detail).font(.caption).foregroundStyle(Theme.ink3)
                        }
                        Spacer()
                        Text(StorageUsage.format(item.bytes)).monospacedDigit().foregroundStyle(Theme.ink2)
                        if item.kind.clearable {
                            Button("清理") { clear(item.kind) }
                                .buttonStyle(.borderless).foregroundStyle(Theme.accent)
                                .disabled(item.bytes == 0)
                                .accessibilityIdentifier("storage.clear.\(item.kind.rawValue)")
                        }
                    }
                    .frame(minHeight: 44)
                }
            } header: { Text("分项") } footer: { Text("清理缓存不会删除书籍、进度或书摘；语音缓存清理后，云语音会在下次朗读时重新合成。") }
            .listRowBackground(Theme.surface)

            Section {
                Button("清理全部缓存") { confirmAll = true }
                    .accessibilityIdentifier("storage.clearAll")
                Button("修复书库索引") {
                    model.clearIndexCache()
                    model.notify("已重建封面与分类索引。")
                    rescan()
                }
            } footer: { Text("书架上的封面、分类显示不对或书籍消失时，可以修复书库索引；书籍文件本身不会改动。") }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("空间整理")
        .navigationBarTitleDisplayMode(.inline)
        .task { rescan() }
        .confirmationDialog("清理全部缓存？", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("清理", role: .destructive) { StorageUsage.Kind.allCases.filter(\.clearable).forEach(clear) }
        } message: { Text("书籍、进度和书摘会保留。") }
    }

    private func rescan() {
        scanning = true
        Task {
            let result = await Task.detached(priority: .utility) { StorageUsage.scan() }.value
            usage = result; scanning = false
        }
    }
    private func clear(_ kind: StorageUsage.Kind) {
        StorageUsage.clear(kind)
        if kind == .covers { model.clearIndexCache() }
        model.notify("已清理\(kind.title)。")
        rescan()
    }
}

/// 存储占用的统计与清理，不依赖界面，便于测试。
enum StorageUsage {
    enum Kind: String, CaseIterable, Sendable {
        case library, speech, covers, temporary
        var title: String { ["library": "书库", "speech": "语音缓存", "covers": "封面与其他缓存", "temporary": "临时文件"][rawValue]! }
        var detail: String {
            switch self {
            case .library: "书籍、资源、进度与书摘"
            case .speech: "云语音合成的音频"
            case .covers: "封面缩略图、分类索引"
            case .temporary: "导入、导出与分享时的中间文件"
            }
        }
        var clearable: Bool { self != .library }
        var url: URL? {
            let fm = FileManager.default
            switch self {
            case .library: return fm.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("TingyeNative")
            case .speech: return fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("TTSAudio")
            case .covers: return fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            case .temporary: return fm.temporaryDirectory
            }
        }
    }
    struct Item: Identifiable, Sendable { let kind: Kind; let bytes: Int64; var id: String { kind.rawValue } }

    static func scan() -> [Item] {
        let speech = size(of: Kind.speech.url)
        return Kind.allCases.map { kind in
            // 「封面与其他缓存」不重复计入语音缓存。
            Item(kind: kind, bytes: kind == .covers ? max(0, size(of: kind.url) - speech) : size(of: kind.url))
        }
    }
    static func size(of url: URL?) -> Int64 {
        guard let url, let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
    static func clear(_ kind: Kind) {
        guard kind.clearable, let folder = kind.url else { return }
        let fm = FileManager.default
        if kind == .speech { CloudSpeech.clearDiskCache(); return }
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            // 清「封面与其他缓存」时保留语音缓存，由它自己的按钮处理。
            if kind == .covers && url.lastPathComponent == "TTSAudio" { continue }
            try? fm.removeItem(at: url)
        }
    }
    static func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
