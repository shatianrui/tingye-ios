import Foundation
import UIKit
import ReadiumShared
import ReadiumNavigator

/// 使用 reader.font 的同一套键。UIFont 注册只服务原生层，WebView 必须有字体文件声明。
enum ReadiumFontProvider {
    struct FontFile: Equatable {
        let key: String
        let url: URL
        let postScript: String
    }
    static let system: FontFamily = "-apple-system"
    static func files(bundle: Bundle = .main, custom: [CustomFont] = FontLibrary.fonts) -> [FontFile] {
        let bundled = ReaderPreferences.bundledFonts.sorted { $0.key < $1.key }.compactMap { key, name -> FontFile? in
            let ext = ["serif", "hansans"].contains(key) ? "otf" : "ttf"
            guard let url = bundle.url(forResource: name, withExtension: ext),
                  FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            return FontFile(key: key, url: url, postScript: name)
        }
        return bundled + custom.compactMap { font in
            // 库记录不是任意文件访问授权。
            guard font.file == URL(fileURLWithPath: font.file).lastPathComponent else { return nil }
            let url = FontLibrary.folder.appendingPathComponent(font.file)
            guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            return FontFile(key: "custom:" + font.postScript, url: url, postScript: font.postScript)
        }
    }
    static func family(for key: String, files: [FontFile]) -> FontFamily {
        guard let file = files.first(where: { $0.key == key }) else { return system }
        return FontFamily(rawValue: file.postScript)
    }
    static func declarations(files: [FontFile]) -> [AnyHTMLFontFamilyDeclaration] {
        files.compactMap { file in
            guard let source = FileURL(url: file.url) else { return nil }
            let declaration = CSSFontFamilyDeclaration(
                fontFamily: FontFamily(rawValue: file.postScript), alternates: [system, .sansSerif],
                fontFaces: [CSSFontFace(file: source)]
            )
            // Toolkit 把本地文件改成 readium:// 路由；TTC face fragment 必须在改写后附上。
            return CollectionDeclaration(base: declaration, face: file.url.pathExtension.lowercased() == "ttc" ? file.postScript : nil)
                .eraseToAnyHTMLFontFamilyDeclaration()
        }
    }
    private struct CollectionDeclaration: HTMLFontFamilyDeclaration {
        let base: CSSFontFamilyDeclaration
        let face: String?
        var fontFamily: FontFamily { base.fontFamily }
        var alternates: [FontFamily] { base.alternates }
        func inject(in html: String, servingFile: (FileURL) throws -> any AbsoluteURL) throws -> String {
            try base.inject(in: html) { source -> any AbsoluteURL in
                let served = try servingFile(source)
                guard let face, var components = URLComponents(string: served.string) else { return served }
                components.fragment = face
                return components.string.flatMap { AnyURL(string: $0)?.absoluteURL } ?? served
            }
        }
    }
    static func lineHeight(for key: String, size: Double, files: [FontFile]) -> Double {
        let name = files.first { $0.key == key }?.postScript
        return Double(name.flatMap { UIFont(name: $0, size: size) }?.lineHeight ?? UIFont.systemFont(ofSize: size).lineHeight)
    }
}
