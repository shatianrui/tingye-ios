import SwiftUI

/// v29 阶段三（p3b）：统一摘记（呈现层）。
/// 把每本书的划线、笔记与书签合并为一个按时间倒序的列表，类型角标区分；
/// 底层 Highlight / Bookmark 格式与存储一字不改，删除与跳转全部复用既有 API：
/// 删划线走 `removeHighlight`（确认文案沿用 NotesList），删书签走 `bookmark` 切换，
/// 回到原文走 `open(_:chapter:position:)`。导出在本视图内组装 Markdown，补章节与日期。
struct NotesUnifiedView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
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
            query.isEmpty
                || $0.text.localizedCaseInsensitiveContains(query)
                || ($0.noteText ?? "").localizedCaseInsensitiveContains(query)
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
            if !hasAnyItems {
                ContentUnavailableView("还没有摘记", systemImage: Icon.highlight, description: Text("长按正文添加标注、写笔记，或在阅读与听书时加书签，都会收进这里。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(books) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item, entry: group.entry)
                    }
                } header: {
                    HStack(spacing: 8) {
                        BookCoverView(title: group.entry.title, color: group.entry.color, image: model.covers[group.entry.id], width: 24)
                        Text(group.entry.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).textCase(nil)
                        SealBadge(text: "\(group.items.count) 条", color: Theme.gold, background: Theme.goldSoft)
                        Spacer()
                        ShareLink(item: Self.markdown(group.entry)) { Label("导出", systemImage: Icon.share).font(.caption.weight(.medium)).foregroundStyle(Theme.accent).frame(minHeight: 44) }
                            .accessibilityLabel("导出《\(group.entry.title)》摘记")
                    }
                }
            }
        }
        .navigationTitle("书摘与笔记")
        .searchable(text: $query, prompt: "搜索划线、笔记与书签")
        .scrollContentBackground(.hidden)
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

    private func row(_ item: Item, entry: ShelfEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.open(entry, chapter: item.chapter, position: item.position) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(item.kind.rawValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accentSoft, in: Capsule())
                        Text("第 \(item.chapter + 1) 章").lineLimit(1)
                        Spacer()
                        Text(item.date.formatted(date: .abbreviated, time: .omitted))
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.ink3)
                    Text(item.text)
                        .font(Theme.serif(17, relativeTo: .body))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, 11)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(item.highlight.map { ReaderMark.color($0.color) } ?? Theme.accent)
                                .frame(width: 2.5)
                        }
                    if let noteText = item.noteText {
                        Text(noteText)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            .padding(.top, 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 14) {
                Button { model.open(entry, chapter: item.chapter, position: item.position) } label: {
                    Label("回到原文", systemImage: Icon.read).frame(minHeight: 44)
                }
                Spacer(minLength: 0)
                Button(role: .destructive) { beginRemoval(item, entry: entry) } label: {
                    Label(item.kind == .bookmark ? "移除书签" : "删除标注…", systemImage: Icon.delete).frame(minHeight: 44)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
        .listRowBackground(Theme.surface)
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
