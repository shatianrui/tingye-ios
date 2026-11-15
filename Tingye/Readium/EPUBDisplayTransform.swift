import Foundation

/// 单元 3/4 的显示资源转换接口；本单元不执行简繁转换。
///
/// 合同：只包装 Publication 的按需 XHTML Resource，遍历 DOM 文本节点，禁止替换 innerHTML。
/// 不修改 source.epub、派生缓存、Book.chapter.text、marks 或已保存的引用。
/// 必须同时产出原文 UTF-16 ↔ 显示 UTF-16 ↔ DOM range 映射（包括长度变化、实体、ruby、空白）。
/// 进度/选区/Locator 持久化永远使用原文坐标，显示选区通过 TextDOMIndex 双向往返。
/// mode 切换应重新供应资源并恢复原文 Locator；通过往返验收前不能宣称支持 EPUB 简繁。
protocol EPUBDisplayTransform {
    func transform(xhtml: Data, href: String, mode: String) async throws -> EPUBDisplayResource
}

struct EPUBDisplayResource {
    let xhtml: Data
    /// 双向映射必须覆盖所有可选文本；不能仅假定简繁转换等长。
    let originalToDisplay: [NSRange: NSRange]
}
