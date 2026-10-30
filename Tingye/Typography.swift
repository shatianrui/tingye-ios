import SwiftUI
import CoreText
import UniformTypeIdentifiers

// MARK: - 简繁转换

enum ChineseConvert {
    /// 只做字形转换，不改变长度：句子坐标（阅读进度、划线、朗读高亮）仍然对得上。
    /// 个别字转换后 UTF-16 长度变化时，整章保持原文，宁可不转也不让坐标错位。
    static func apply(_ text: String, _ mode: String) -> String {
        let transform: StringTransform
        switch mode {
        case "s2t": transform = StringTransform("Hans-Hant")
        case "t2s": transform = StringTransform("Hant-Hans")
        default: return text
        }
        guard let converted = text.applyingTransform(transform, reverse: false), converted.utf16.count == text.utf16.count else { return text }
        return converted
    }
}

// MARK: - 导入字体（参照 PureLibro「我的字体」）

struct CustomFont: Codable, Identifiable, Hashable, Sendable {
    var id: String { postScript }
    var file: String
    var postScript: String
    var name: String
}

enum FontLibrary {
    private static let key = "fonts.custom"
    static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var fonts: [CustomFont] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CustomFont].self, from: data)) ?? []
    }
    private static func save(_ list: [CustomFont]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// 启动时注册已导入的字体（仅本进程可见）
    static func registerAll() {
        for font in fonts { CTFontManagerRegisterFontsForURL(folder.appendingPathComponent(font.file) as CFURL, .process, nil) }
    }

    /// 复制字体文件到 App 目录并注册；一个文件可能包含多个字重
    static func importFont(_ url: URL) throws -> [CustomFont] {
        let secured = url.startAccessingSecurityScopedResource(); defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else { throw ReaderError.message("请选择 TTF、OTF 或 TTC 字体文件。") }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 60 * 1024 * 1024 else { throw ReaderError.message("字体文件超过 60 MB。") }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else {
            throw ReaderError.message("无法读取这个字体文件。")
        }
        let fileName = UUID().uuidString + "." + ext
        let target = folder.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: url, to: target)
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(target as CFURL, .process, &error) {
            let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
            // 已经注册过同名字体（重复导入）不算失败
            if code != CTFontManagerError.alreadyRegistered.rawValue {
                try? FileManager.default.removeItem(at: target)
                throw ReaderError.message("字体注册失败。")
            }
        }
        var list = fonts
        var added: [CustomFont] = []
        for descriptor in descriptors {
            guard let postScript = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String, !list.contains(where: { $0.postScript == postScript }) else { continue }
            let display = (CTFontDescriptorCopyLocalizedAttribute(descriptor, kCTFontDisplayNameAttribute, nil) as? String) ?? postScript
            let font = CustomFont(file: fileName, postScript: postScript, name: display)
            list.append(font); added.append(font)
        }
        if added.isEmpty { try? FileManager.default.removeItem(at: target); throw ReaderError.message("这个字体已经导入过了。") }
        save(list)
        return added
    }

    static func remove(_ font: CustomFont) {
        var list = fonts
        list.removeAll { $0.postScript == font.postScript }
        save(list)
        // 同一文件的其他字重都删掉后再移除文件
        if !list.contains(where: { $0.file == font.file }) {
            let url = folder.appendingPathComponent(font.file)
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// 我的字体：导入、预览、选用、删除
struct MyFontsView: View {
    @AppStorage("reader.font") private var font = "serif"
    @EnvironmentObject var model: AppModel
    @State private var fonts = FontLibrary.fonts
    @State private var importing = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("让文字更合心意", systemImage: Icon.fonts).font(.headline).foregroundStyle(Theme.ink)
                    Text("山静似太古，日长如小年。")
                        .font(Theme.serif(22)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("在阅读排版中选用内置字体，也可以导入自己的字体。原文阅读与文字模式共用字体偏好。")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                }.padding(.vertical, 10)
            }.listRowBackground(Theme.accentSoft)
            Section {
                ForEach(fonts) { item in
                    Button { font = "custom:" + item.postScript } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.subheadline).foregroundStyle(Theme.ink3)
                                Text("山静似太古，日长如小年。").font(.custom(item.postScript, size: 19)).foregroundStyle(Theme.ink)
                            }
                            Spacer()
                            if font == "custom:" + item.postScript { Image(systemName: Icon.checkmark).foregroundStyle(Theme.accent) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            if font == "custom:" + item.postScript { font = "serif" }
                            FontLibrary.remove(item); fonts = FontLibrary.fonts
                        } label: { Label("删除", systemImage: Icon.delete) }
                    }
                }
                Button { importing = true } label: { Label("导入字体文件", systemImage: Icon.addFont) }
            } footer: {
                Text("支持 TTF、OTF、TTC。字体只保存在这台设备，只用于正文，请确认字体授权允许个人使用。左滑删除。")
            }
        }
        .navigationTitle("我的字体")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .paperBackground()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.font, UTType(filenameExtension: "ttf") ?? .data, UTType(filenameExtension: "otf") ?? .data], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            var errors: [String] = []
            for url in urls {
                do { _ = try FontLibrary.importFont(url) } catch { errors.append(url.lastPathComponent + "：" + error.localizedDescription) }
            }
            fonts = FontLibrary.fonts
            if let last = fonts.last, errors.isEmpty { font = "custom:" + last.postScript }
            if !errors.isEmpty { model.message = errors.joined(separator: "\n") }
        }
    }
}
