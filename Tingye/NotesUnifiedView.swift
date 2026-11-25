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
            Masthead(title: "留下的文字", subtitle: "划线、笔记与书签，按书收好，随时回到原文。", kicker: "摘记", titleSize: 28)
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
                        BookCoverView(title: group.entry.title, color: group.entry.color, image: model.covers[group.entry.id], width: 24)
                        Text(group.entry.title).font(Theme.serif(17)).foregroundStyle(Theme.ink).textCase(nil)
                        SealBadge(text: "\(group.items.count) 条", color: Theme.ink3, background: Theme.surface2)
                        Spacer()
                        ShareLink(item: Self.markdown(group.entry)) { Label("导出", systemImage: Icon.share).font(.caption.weight(.medium)).foregroundStyle(Theme.clayDeep).frame(minHeight: Theme.iconButtonSize) }
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

    private func row(_ item: Item, entry: ShelfEntry) -> some View {
        let markColor = accentColor(for: item)
        return PaperCard(padding: Theme.cardInset) {
            VStack(alignment: .leading, spacing: Theme.space2) {
                Button { model.open(entry, target: item.target) } label: {
                    HStack(alignment: .top, spacing: Theme.space3) {
                        Capsule().fill(markColor)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: Theme.space2) {
                                SealBadge(text: item.kind.rawValue,
                                          color: item.kind == .note ? Theme.accent : Theme.ink2,
                                          background: item.kind == .note ? Theme.accentSoft : Theme.surface2)
                                Text("CH \(String(format: "%02d", item.chapter + 1))")
                                    .font(Theme.sans(11, weight: .medium)).monospacedDigit().foregroundStyle(Theme.ink3)
                                Spacer(minLength: 0)
                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(Theme.sans(11)).monospacedDigit().foregroundStyle(Theme.ink3)
                            }
                            Text(item.text).font(Theme.serif(16, relativeTo: .body))
                                .lineSpacing(5).foregroundStyle(Theme.ink).lineLimit(5)
                            if let noteText = item.noteText {
                                Text(noteText).font(Theme.sans(13.5)).foregroundStyle(Theme.ink2)
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.rule) }
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
                            .font(Theme.sans(12.5, weight: .medium))
                            .frame(minHeight: 32)
                    }.foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                    Button(role: .destructive) { beginRemoval(item, entry: entry) } label: {
                        Label(item.kind == .bookmark ? "移除书签" : "删除", systemImage: Icon.delete)
                            .font(Theme.sans(12.5))
                            .frame(minHeight: 32)
                    }.foregroundStyle(Theme.danger)
                }
                .buttonStyle(.borderless)
            }
        }
        .listRowInsets(EdgeInsets(top: Theme.space1, leading: 0, bottom: Theme.space1, trailing: 0))
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
    static func markdown(_ entry: ShelfEntry) -> String {
        var lines = ["# 《\(entry.title)》摘记", "", "\(entry.author)", ""]
        for item in unifiedItems(for: entry) {
            lines.append("## \(item.kind.rawValue) · 第 \(item.chapter + 1) 章 · \(item.date.formatted(date: .abbreviated, time: .omitted))")
            lines.append("")
            lines.append("> \(item.text)")
            if let noteText = item.noteText { lines.append(""); lines.append(noteText) }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
