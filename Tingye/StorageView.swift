import SwiftUI

/// 空间整理：分项统计书库、语音缓存、封面索引与临时文件的占用，并可分别清理；附书库索引修复。
struct StorageView: View {
    @EnvironmentObject var model: AppModel
    @State private var usage: [StorageUsage.Item] = []
    @State private var scanning = false
    @State private var confirmAll = false
    @State private var confirmKind: StorageUsage.Kind?

    var body: some View {
        SettingsPage(title: "空间整理") {
            SettingsGroup(title: "总占用") {
                if scanning && usage.isEmpty {
                    IndexStatus(kind: .loading, title: Text("正在统计…"))
                } else {
                    IndexMetric(value: Text(verbatim: StorageUsage.format(usage.reduce(0) { $0 + $1.bytes })),
                                label: Text("书库、缓存与临时文件"), large: true)
                    usageBar.padding(.top, Theme.space3)
                    if scanning { ProgressView("正在统计…").padding(.top, Theme.space2) }
                }
            }
            SettingsGroup(title: "分项") {
                ForEach(usage) { item in
                    IndexRowLabel(title: Text(L(item.kind.title)),
                                  detail: Text("\(StorageUsage.format(item.bytes)) · \(L(item.kind.detail))"))
                    if item.id != usage.last?.id { IndexRule() }
                }
            }
            SettingsGroup(title: "清理缓存", footer: "清理缓存不会删除书籍、进度或书摘；语音缓存清理后，云语音会在下次朗读时重新合成。") {
                ForEach(usage.filter { $0.kind.clearable }) { item in
                    Button { confirmKind = item.kind } label: {
                        IndexRowLabel(title: Text(L(item.kind.title)),
                                      detail: item.bytes == 0 ? Text("没有可清理的缓存") : Text(verbatim: StorageUsage.format(item.bytes)),
                                      symbol: Icon.delete, disclosure: item.bytes > 0)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.bytes == 0)
                    .accessibilityIdentifier("storage.clear.\(item.kind.rawValue)")
                    IndexRule()
                }
                Button(role: .destructive) { confirmAll = true } label: {
                    IndexActionLabel(title: "清理全部缓存", symbol: Icon.delete)
                        .foregroundStyle(IndexTheme.danger).frame(minHeight: Theme.iconButtonSize)
                }
                .accessibilityIdentifier("storage.clearAll")
            }
            SettingsGroup(footer: "书架上的封面、分类显示不对或书籍消失时，可以修复书库索引；书籍文件本身不会改动。") {
                Button("修复书库索引") {
                    model.clearIndexCache()
                    model.notify("已重建封面与分类索引。")
                    rescan()
                }.buttonStyle(IndexActionStyle(role: .secondary))
            }
        }
        .navigationTitle("空间整理").navigationBarTitleDisplayMode(.inline)
        .task { rescan() }
        .confirmationDialog("清理全部缓存？", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("清理", role: .destructive) { StorageUsage.Kind.allCases.filter(\.clearable).forEach(clear) }
        } message: { Text("书籍、进度和书摘会保留。") }
        .confirmationDialog("清理缓存？", isPresented: Binding(get: { confirmKind != nil }, set: { if !$0 { confirmKind = nil } }), titleVisibility: .visible) {
            Button("清理", role: .destructive) {
                if let kind = confirmKind { clear(kind) }
                confirmKind = nil
            }
            Button("取消", role: .cancel) { confirmKind = nil }
        } message: { Text("书籍、进度和书摘会保留。") }
    }

    private var usageBar: some View {
        let books = usage.filter { $0.kind == .library || $0.kind == .originals }.reduce(Int64(0)) { $0 + $1.bytes }
        let cache = usage.filter { $0.kind == .derived || $0.kind == .speech || $0.kind == .covers }.reduce(Int64(0)) { $0 + $1.bytes }
        let other = usage.filter { $0.kind == .temporary }.reduce(Int64(0)) { $0 + $1.bytes }
        let total = max(1, books + cache + other)
        return VStack(alignment: .leading, spacing: Theme.space3) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle().fill(IndexTheme.accent).frame(width: geometry.size.width * CGFloat(books) / CGFloat(total))
                    Rectangle().fill(IndexTheme.edge).frame(width: geometry.size.width * CGFloat(cache) / CGFloat(total))
                    Rectangle().fill(IndexTheme.rule).frame(width: geometry.size.width * CGFloat(other) / CGFloat(total))
                }.clipShape(Capsule())
            }.frame(height: Theme.progressHeight).background(IndexTheme.rule, in: Capsule()).accessibilityHidden(true)
            // Text names and values accompany all three segments; color is never the only key.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.space4) { usageLegend(books: books, cache: cache, other: other) }
                VStack(alignment: .leading, spacing: Theme.space2) { usageLegend(books: books, cache: cache, other: other) }
            }
        }
    }

    private func usageLegend(books: Int64, cache: Int64, other: Int64) -> some View {
        Group {
            legend(Text("书籍 · \(StorageUsage.format(books))"), color: IndexTheme.accent)
            legend(Text("缓存 · \(StorageUsage.format(cache))"), color: IndexTheme.edge)
            legend(Text("其他 · \(StorageUsage.format(other))"), color: IndexTheme.rule)
        }.font(Theme.sans(13)).monospacedDigit().foregroundStyle(IndexTheme.muted)
    }

    private func legend(_ title: Text, color: Color) -> some View {
        HStack(spacing: Theme.space1) {
            RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(color)
                .frame(width: Theme.space2, height: Theme.space2).accessibilityHidden(true)
            title
        }
    }

    private func rescan() {
        scanning = true
        Task {
            let result = await Task.detached(priority: .utility) { StorageUsage.scan() }.value
            usage = result; scanning = false
        }
    }
    private func clear(_ kind: StorageUsage.Kind) {
        Task {
            do {
                if kind == .derived { try await model.publicationStore().clearCache() }
                else { StorageUsage.clear(kind) }
                if kind == .covers { model.clearIndexCache() }
                model.notify(kind == .derived ? "已清理当前书库的 EPUB 派生缓存。" : "已清理\(kind.title)。")
                rescan()
            } catch { model.message = error.localizedDescription }
        }
    }
}

/// 存储占用的统计与清理，不依赖界面，便于测试。
enum StorageUsage {
    enum Kind: String, CaseIterable, Sendable {
        case library, originals, derived, speech, covers, temporary
        var title: String { ["library": "书库文本与摘记", "originals": "书库原 EPUB", "derived": "EPUB 派生缓存", "speech": "语音缓存", "covers": "封面与其他缓存", "temporary": "临时文件"][rawValue]! }
        var detail: String {
            switch self {
            case .library: "书籍文本、资源、进度与书摘"
            case .originals: "书库的一部分，随备份保存的原文件"
            case .derived: "清理当前书库的可重建文件；保留正在阅读的文件与其他书库缓存"
            case .speech: "云语音合成的音频"
            case .covers: "封面缩略图、分类索引"
            case .temporary: "导入、导出与分享时的中间文件"
            }
        }
        var clearable: Bool { self != .library && self != .originals }
        var url: URL? {
            let fm = FileManager.default
            switch self {
            case .library: return fm.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("TingyeNative")
            case .originals: return nil
            case .derived: return fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("TingyeReadium")
            case .speech: return fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("TTSAudio")
            case .covers: return fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            case .temporary: return fm.temporaryDirectory
            }
        }
    }
    struct Item: Identifiable, Sendable { let kind: Kind; let bytes: Int64; var id: String { kind.rawValue } }

    static func scan(libraryRoot: URL? = nil, derivedRoot: URL? = nil) -> [Item] {
        let library = libraryRoot ?? Kind.library.url
        let originals: Int64
        if let libraryRoot { originals = size(of: libraryRoot.appendingPathComponent("Publications")) }
        else {
            originals = ((try? FileManager.default.contentsOfDirectory(at: library ?? URL(fileURLWithPath: "/nonexistent"), includingPropertiesForKeys: nil)) ?? [])
                .reduce(0) { $0 + size(of: $1.appendingPathComponent("Publications")) }
        }
        let speech = size(of: Kind.speech.url)
        let allDerived = size(of: Kind.derived.url)
        return Kind.allCases.map { kind in
            let bytes: Int64
            switch kind {
            case .library: bytes = max(0, size(of: library) - originals)
            case .originals: bytes = originals
            case .derived: bytes = size(of: derivedRoot ?? kind.url)
            case .covers: bytes = max(0, size(of: kind.url) - speech - allDerived)
            default: bytes = size(of: kind.url)
            }
            return Item(kind: kind, bytes: bytes)
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
        guard kind.clearable, kind != .derived, let folder = kind.url else { return }
        let fm = FileManager.default
        if kind == .speech { CloudSpeech.clearDiskCache(); return }
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            // 清「封面与其他缓存」时保留语音缓存，由它自己的按钮处理。
            if kind == .covers && ["TTSAudio", "TingyeReadium"].contains(url.lastPathComponent) { continue }
            try? fm.removeItem(at: url)
        }
    }
    static func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
