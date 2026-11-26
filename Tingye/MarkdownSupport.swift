import SwiftUI

// A 档轻量增强（build 153）：摘记笔记的富文本渲染。
// 本文件只引入 MarkdownUI —— swift-markdown 的模块名就叫 Markdown，而
// MarkdownUI 的 View 类型也叫 Markdown，两者同处一个文件会产生名字歧义，
// 因此 AST 解析能力刻意放在 BookImporter.swift（那里的 import 互不干扰）。
// 全程 #if canImport 兜底：product 未链接时工程仍可编译，能力回退为纯文本。
#if canImport(MarkdownUI)
import MarkdownUI
#endif

enum MarkdownSupport {
    /// 摘记正文：优先按 Markdown 富文本渲染（标题、粗体、链接、列表、代码块），
    /// 依赖不可用时回退为纯文本，保证无签名构建与可选依赖解耦。
    @ViewBuilder
    static func note(_ text: String) -> some View {
        #if canImport(MarkdownUI)
        MarkdownUI.Markdown(text)
        #else
        Text(text)
        #endif
    }

    /// 诊断用：MarkdownUI 是否链接到当前 target。
    static var isAvailable: Bool {
        #if canImport(MarkdownUI)
        true
        #else
        false
        #endif
    }
}
