import SwiftUI

/// v29 阶段三（p3b）：统一摘记（呈现层）。
/// 把每本书的划线、笔记与书签合并为一个按时间倒序的列表，类型角标区分；
/// 底层 Highlight / Bookmark 格式与存储一字不改，删除与跳转全部复用既有 API：
/// 删划线走 `removeHighlight`（确认文案沿用 NotesList），删书签走 `bookmark` 切换，
/// 回到原文走 `open(_:chapter:position:)`。导出在本视图内组装 Markdown，补章节与日期。
struct NotesUnifiedView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var selectedKind: Item.Kind?
    @State private var removingHighlight: Highlight?
    @State private var removingHighlightEntryID: String?
    @State private var removingBookmark: Bookmark?
    @State private var removingBookmarkEntryID: String?

    struct Item: Identifiable {
        enum Kind: String {
            case highlight = "划线"
            case note = "笔记"
            case bookmark = "书签"
        }
        let kind: Kind
        let chapter: Int
        let position: Int
        let text: String
        let noteText: String?
        let date: Date
        let highlight: Highlight?
        let bookmark: Bookmark?
        var target: LocatorTarget {
            if let bookmark { return .init(bookmark) }
            if let highlight { return .init(highlight) }
            return .init(chapter: chapter, position: position)
        }
        var id: String {
            if let bookmark { return "bookmark-" + bookmark.id.uuidString }
            return "highlight-" + (highlight?.id.uuidString ?? "")
        }
    }

    /// 一本书的全部摘记（划线 / 笔记 / 书签），按时间倒序。导出与列表共用同一份组装。
    static func unifiedItems(for entry: ShelfEntry) -> [Item] {
        var result: [Item] = entry.notes.map { highlight in
            Item(kind: highlight.note == nil ? .highlight : .note,
                 chapter: highlight.chapter, position: highlight.start,
                 text: highlight.text, noteText: highlight.note, date: highlight.date,
                 highlight: highlight, bookmark: nil)
        }
        result += entry.bookmarks.map { bookmark in
            Item(kind: .bookmark,
                 chapter: bookmark.chapter, position: bookmark.position,
                 text: bookmark.excerpt, noteText: nil, date: bookmark.date,
                 highlight: nil, bookmark: bookmark)
        }
        return result.sorted { $0.date > $1.date }
    }

    private func filteredItems(for entry: ShelfEntry) -> [Item] {
        Self.unifiedItems(for: entry).filter {
            (selectedKind == nil || $0.kind == selectedKind)
                && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)
                    || ($0.noteText ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    private struct BookGroup: Identifiable {
        let entry: ShelfEntry
        let items: [Item]
        var id: String { entry.id }
    }

    private var books: [BookGroup] {
        model.visibleEntries
            .map { BookGroup(entry: $0, items: filteredItems(for: $0)) }
            .filter { !$0.items.isEmpty }
            .sorted { ($0.items.first?.date ?? .distantPast) > ($1.items.first?.date ?? .distantPast) }
    }

    private var hasAnyItems: Bool {
        model.visibleEntries.contains { !$0.notes.isEmpty || !$0.bookmarks.isEmpty }
    }

    var body: some View {
        List {
            Masthead(title: "留下的文字", subtitle: "每一次心动与停驻，都为你按书轻轻收好。", kicker: "摘记卡片墙", titleSize: 28)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.space2) {
                    Chip(title: "全部", selected: selectedKind == nil) { selectedKind = nil }
                    ForEach([Item.Kind.highlight, .note, .bookmark], id: \.rawValue) { kind in
                        Chip(title: kind.rawValue, selected: selectedKind == kind) { selectedKind = kind }
                    }
                }
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            if !hasAnyItems {
                EmptyState(title: "还没有摘记", detail: "长按正文添加标注、写笔记，或在阅读与听书时加书签，都会收进这里。")
                    .listRowBackground(Color.clear)
            }
            if hasAnyItems && books.isEmpty {
                EmptyState(title: "没有匹配的摘记", detail: query.isEmpty ? "试试其他类型。" : "没有找到包含「\(query)」的划线、笔记或书签。").listRowBackground(Color.clear)
            }
            ForEach(books) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item, entry: group.entry)
                    }
                } header: {
                    HStack(spacing: Theme.space2) {
                        BookCoverView(title: group.entry.title, color: group.entry.color, image: model.covers[group.entry.id], width: 26)
                        Text(group.entry.title).font(Theme.serif(17)).foregroundStyle(Theme.ink).textCase(nil)
                        SealBadge(text: "\(group.items.count) 条", color: Theme.butterInk, background: Theme.butter)
                        Spacer()
                        ShareLink(item: Self.markdown(group.entry)) {
                            HStack(spacing: 4) {
                                Image(systemName: Icon.share).font(.system(size: 11.5, weight: .semibold)).accessibilityHidden(true)
                                Text("导出").font(Theme.rounded(12, weight: .semibold))
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.accentSoft, in: Capsule())
                            .frame(minHeight: Theme.iconButtonSize)
                        }
                        .accessibilityLabel("导出《\(group.entry.title)》摘记")
                    }
                }
            }
        }
        .navigationTitle("书摘与笔记").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索划线、笔记与书签")
        .editorialList()
        .background(Theme.bg)
        .confirmationDialog("删除这条标注？", isPresented: Binding(get: { removingHighlight != nil }, set: { if !$0 { removingHighlight = nil } }), titleVisibility: .visible) {
            Button("删除标注与附带笔记", role: .destructive) {
                if let highlight = removingHighlight, let entryID = removingHighlightEntryID {
                    model.removeHighlight(entryID, id: highlight.id)
                }
                removingHighlight = nil
            }
            Button("取消", role: .cancel) { removingHighlight = nil }
        } message: { Text("只删除这条标注及其笔记，书中原文不会改变。") }
        .confirmationDialog("移除这枚书签？", isPresented: Binding(get: { removingBookmark != nil }, set: { if !$0 { removingBookmark = nil } }), titleVisibility: .visible) {
            Button("移除书签", role: .destructive) {
                if let bookmark = removingBookmark, let entryID = removingBookmarkEntryID {
                    model.bookmark(entryID, chapter: bookmark.chapter, position: bookmark.position, excerpt: bookmark.excerpt)
                }
                removingBookmark = nil
            }
            Button("取消", role: .cancel) { removingBookmark = nil }
        } message: { Text("只移除这枚书签，书中原文不会改变。") }
    }

    private func accentColor(for item: Item) -> Color {
        if item.kind == .bookmark { return Theme.accent }
        if let colorName = item.highlight?.color { return ReaderMark.color(colorName) }
        return Theme.accent
    }

    private func badgeStyle(for kind: Item.Kind) -> (fg: Color, bg: Color) {
        switch kind {
        case .note: return (Theme.lavInk, Theme.lav)
        case .bookmark: return (Theme.skyInk, Theme.sky)
        case .highlight: return (Theme.butterInk, Theme.butter)
        }
    }

    private func row(_ item: Item, entry: ShelfEntry) -> some View {
        let markColor = accentColor(for: item)
        let badge = badgeStyle(for: item.kind)
        return VStack(alignment: .leading, spacing: Theme.space2) {
            Button { model.open(entry, target: item.target) } label: {
                HStack(alignment: .top, spacing: Theme.space3) {
                    Capsule().fill(markColor)
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: Theme.space2) {
                            HStack(spacing: 5) {
                                Circle().fill(markColor).frame(width: 6.5, height: 6.5).accessibilityHidden(true)
                                SealBadge(text: item.kind.rawValue, color: badge.fg, background: badge.bg)
                            }
                            Text("第 \(item.chapter + 1) 章")
                                .font(Theme.rounded(11.5, weight: .medium)).monospacedDigit().foregroundStyle(Theme.ink3)
                            Spacer(minLength: 0)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(Theme.rounded(11, weight: .regular)).monospacedDigit().foregroundStyle(Theme.ink3)
                        }
                        Text(item.text).font(Theme.serif(16.5, relativeTo: .body))
                            .lineSpacing(6).foregroundStyle(Theme.ink).lineLimit(5)
                        if let noteText = item.noteText {
                            MarkdownSupport.note(noteText)
                                .font(Theme.sans(13.5)).foregroundStyle(Theme.ink2)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            RowDivider()
            HStack(spacing: Theme.space3) {
                Button { model.open(entry, target: item.target) } label: {
                    Label("回到原文", systemImage: Icon.read)
                        .font(Theme.rounded(12.5, weight: .semibold))
                        .frame(minHeight: 32)
                }.foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
                Button(role: .destructive) { beginRemoval(item, entry: entry) } label: {
                    Label(item.kind == .bookmark ? "移除书签" : "删除", systemImage: Icon.delete)
                        .font(Theme.rounded(12.5, weight: .medium))
                        .frame(minHeight: 32)
                }.foregroundStyle(Theme.danger)
            }
            .buttonStyle(.borderless)
        }
        .padding(Theme.cardInset)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: Theme.rule)
        }
        .softCardShadow()
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowBackground(Color.clear).listRowSeparator(.hidden)
        .swipeActions(allowsFullSwipe: false) {
            Button(role: .destructive) { beginRemoval(item, entry: entry) } label: { Label("删除", systemImage: Icon.delete) }
        }
    }

    private func beginRemoval(_ item: Item, entry: ShelfEntry) {
        if let bookmark = item.bookmark {
            removingBookmarkEntryID = entry.id
            removingBookmark = bookmark
        } else if let highlight = item.highlight {
            removingHighlightEntryID = entry.id
            removingHighlight = highlight
        }
    }

    /// 导出为 Markdown 文本：每条带类型、章节与日期（补齐 AllNotesView 旧导出的缺口）。
    /// build 153：拼装后用 swift-markdown AST 只读复核标题层级，结构一致时附一条
    /// Markdown 渲染不可见的结构摘要；可选依赖不可用时原样返回，导出文件名、编码
    /// 与可访问性标识符不变，笔记与划线正文逐字保留。
    static func markdown(_ entry: ShelfEntry) -> String {
        let items = unifiedItems(for: entry)
        var lines = ["# 《\(entry.title)》摘记", "", "\(entry.author)", ""]
        for item in items {
            lines.append("## \(item.kind.rawValue) · 第 \(item.chapter + 1) 章 · \(item.date.formatted(date: .abbreviated, time: .omitted))")
            lines.append("")
            lines.append("> \(item.text)")
            if let noteText = item.noteText { lines.append(""); lines.append(noteText) }
            lines.append("")
        }
        let raw = lines.joined(separator: "\n")
        guard let structure = BookImporter.markdownStructure(raw),
              structure.topLevel == 1,
              structure.sections == items.count else { return raw }
        return raw + "\n<!-- 结构化导出：\(structure.sections) 条摘记 · \(structure.topLevel) 个文档节 -->\n"
    }
}
