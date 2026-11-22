import SwiftUI
import UIKit

// MARK: - 划线与笔记（参照 PureLibro 的划线菜单：颜色 · 样式 · 笔记 / 复制 / 分享 / 删除）

extension NSAttributedString.Key {
    /// 划线标记：值为 `ReaderMark.Style`，由 CoreTextPageView 在文字下方绘制
    static let tyMark = NSAttributedString.Key("tingye.mark")
}

/// 正文里的一段标记（划线或当前选择），坐标为本章的 UTF-16 范围
struct ReaderMark: Equatable {
    final class Style: NSObject {
        let color: UIColor
        let kind: String
        init(color: UIColor, kind: String) { self.color = color; self.kind = kind }
    }
    var range: NSRange
    var color: String
    /// background / underline / wavy / selection
    var kind: String

    static let palette: [(key: String, name: String, hex: UInt32)] = [
        ("yellow", "琥珀", 0xD69E3A), ("clay", "陶土", 0xA34F36), ("blue", "蓝", 0x4A6FA5), ("pink", "粉", 0xC85A53), ("purple", "紫", 0x7E629E),
    ]
    // 旧标注的颜色是用户内容；仅新建标注的调色盘移除绿色。
    static func uiColor(_ key: String) -> UIColor {
        if key == "green" { return UIColor(hex: 0x4E8E75) }
        return UIColor(hex: palette.first { $0.key == key }?.hex ?? 0xD69E3A)
    }
    static func newColor(_ stored: String?) -> String {
        palette.contains { $0.key == stored } ? (stored ?? "clay") : "clay"
    }
    static func color(_ key: String) -> Color { Color(uiColor: uiColor(key)) }

    var style: Style { Style(color: kind == "selection" ? UIColor(Theme.accent) : Self.uiColor(color), kind: kind) }

    /// 把划线的句区间换成本章字符范围
    static func range(start: Int, end: Int, in sentences: [Sentence]) -> NSRange? {
        guard sentences.indices.contains(start), sentences.indices.contains(end), start <= end else { return nil }
        let a = sentences[start].range.location, b = NSMaxRange(sentences[end].range)
        return NSRange(location: a, length: b - a)
    }

    /// 给一页文字加上与之重叠的标记（pageRange 为该页在本章中的范围）
    static func apply(_ marks: [ReaderMark], to page: NSAttributedString, pageRange: NSRange) -> NSAttributedString {
        let overlapping = marks.filter { NSIntersectionRange($0.range, pageRange).length > 0 }
        guard !overlapping.isEmpty else { return page }
        let result = NSMutableAttributedString(attributedString: page)
        for mark in overlapping {
            let overlap = NSIntersectionRange(mark.range, pageRange)
            result.addAttribute(.tyMark, value: mark.style, range: NSRange(location: overlap.location - pageRange.location, length: overlap.length))
        }
        return result
    }

    /// CoreText 绘制：在一个 run 的字形框下画浅底 / 直线 / 波浪线
    static func draw(_ style: Style, in context: CGContext, box: CGRect) {
        switch style.kind {
        case "background", "selection":
            context.setFillColor(style.color.withAlphaComponent(style.kind == "selection" ? 0.22 : 0.28).cgColor)
            context.addPath(CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil)); context.fillPath()
            if style.kind == "selection" {
                context.setFillColor(style.color.cgColor)
                context.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: 1.5))
            }
        case "underline":
            context.setFillColor(style.color.cgColor)
            context.fill(CGRect(x: box.minX, y: box.minY - 1, width: box.width, height: 2))
        case "wavy":
            context.setStrokeColor(style.color.cgColor)
            context.setLineWidth(1.4)
            let y = box.minY - 1, amplitude: CGFloat = 1.8, wave: CGFloat = 6
            context.move(to: CGPoint(x: box.minX, y: y))
            var x = box.minX
            while x < box.maxX {
                let mid = min(x + wave / 2, box.maxX)
                let next = min(x + wave, box.maxX)
                context.addQuadCurve(to: CGPoint(x: next, y: y), control: CGPoint(x: mid, y: y + (Int((x - box.minX) / wave) % 2 == 0 ? amplitude * 2 : -amplitude * 2)))
                x = next
            }
            context.strokePath()
        default: break
        }
    }
}

/// 当前选择：本章第 start…end 句
struct ReaderSelection: Equatable {
    var chapter: Int
    var start: Int
    var end: Int
}

// MARK: - 选择面板

/// 长按正文后的圆角选段面板；保留颜色、样式与动作的可配置顺序。
struct SelectionPanel: View {
    let text: String
    let existing: Highlight?
    let canExtendBack: Bool
    let canExtendForward: Bool
    let tint: Color
    var paper: Color = IndexTheme.surface
    var accent: Color = IndexTheme.accent
    let onMark: (_ color: String, _ style: String) -> Void
    let onRemove: () -> Void
    let onNote: () -> Void
    let onListen: () -> Void
    let onCopy: () -> Void
    let onExtend: (_ delta: Int) -> Void
    let onClose: () -> Void
    @AppStorage("highlight.lastColor") private var lastColor = "clay"
    @AppStorage("highlight.lastStyle") private var lastStyle = "background"

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tool: Tool = SelectionTool.visible().first ?? .mark
    @State private var chosenColor = "clay"
    @State private var chosenStyle = "background"
    @State private var removing = false
    private typealias Tool = SelectionTool
    private let tools = SelectionTool.visible()

    var body: some View {
        ViewThatFits(in: .vertical) {
            panelContent
            ScrollView { panelContent }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: 520, maxHeight: 520)
        }
        .onAppear {
            chosenColor = existing?.color ?? ReaderMark.newColor(lastColor)
            chosenStyle = existing?.style ?? lastStyle
        }
        .onChange(of: existing?.id) { _, nextID in
            // 同一面板可直接切到另一条标注；扩选变为新选区时保留当前草稿。
            guard nextID != nil, let existing else { return }
            chosenColor = existing.color
            chosenStyle = existing.style
        }
        .confirmationDialog("删除这条标注？", isPresented: $removing, titleVisibility: .visible) {
            Button("删除标注与附带笔记", role: .destructive, action: onRemove)
            Button("取消", role: .cancel) { }
        } message: { Text("只删除这条标注及其笔记，书中原文不会改变。") }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            HStack {
                IndexHeading(title: Text("选段与标注"))
                Spacer()
                Menu {
                    Button { onExtend(-1) } label: { Label("向前多选一句", systemImage: Icon.extendBack) }
                        .disabled(!canExtendBack)
                    Button { onExtend(1) } label: { Label("向后多选一句", systemImage: Icon.extendForward) }
                        .disabled(!canExtendForward)
                } label: {
                    Label("扩大选区", systemImage: Icon.extendRange)
                        .font(.caption.weight(.medium)).frame(minHeight: 44)
                }
                .disabled(!canExtendBack && !canExtendForward)
                Button(action: onClose) {
                    ThemeIcon(symbol: Icon.close, size: 20)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("取消选择")
            }
            .buttonStyle(.plain)
            Text(text)
                .font(IndexTheme.editorial(18, relativeTo: .body)).lineLimit(typeSize.isAccessibilitySize ? nil : 4).lineSpacing(6)
                .padding(Theme.space4).frame(maxWidth: .infinity, alignment: .leading)
                .background(IndexTheme.wash, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
            IndexScopePicker(options: tools, selection: tool, title: { Text(L($0.rawValue)) }, onSelect: { tool = $0 })
            Group {
                switch tool {
                case .mark: markTools
                case .note:
                    VStack(alignment: .leading, spacing: Theme.space3) {
                        if let note = existing?.note, !note.isEmpty {
                            Text(note).font(.subheadline).lineLimit(3).foregroundStyle(IndexTheme.muted)
                        } else {
                            Text("给这段文字，留一点自己的想法。")
                                .font(.subheadline).foregroundStyle(IndexTheme.muted)
                        }
                        action(existing?.note == nil ? "写笔记" : "编辑笔记", Icon.note, onNote, prominent: true)
                    }
                case .quote:
                    VStack(spacing: Theme.space2) {
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.space1)) : AnyLayout(HStackLayout(spacing: Theme.space2))) {
                            action("复制原文", Icon.copy, onCopy)
                            ShareLink(item: text) { IndexActionLabel(title: "分享选段", symbol: Icon.share) }
                                .buttonStyle(IndexActionStyle(role: .secondary, expands: true))
                        }
                        action("从这里开始听", Icon.listen, onListen)
                    }
                }
            }
        }
        .foregroundStyle(IndexTheme.ink)
        .padding(.horizontal, Theme.space4)
        .padding(.top, Theme.space2)
        .padding(.bottom, Theme.space4)
        .frame(maxWidth: 520)
        .indexPanel(fill: paper)
    }

    private var markTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            IndexHeading(title: Text("标注颜色"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.space1),
                                    count: typeSize.isAccessibilitySize ? 2 : 5), spacing: Theme.space1) {
                ForEach(ReaderMark.palette, id: \.key) { item in
                    Button {
                        chosenColor = item.key
                        lastColor = item.key
                    } label: {
                        VStack(spacing: 4) {
                            Circle().fill(Color(uiColor: UIColor(hex: item.hex)))
                                .frame(width: 24, height: 24)
                                .overlay { if chosenColor == item.key { Image(systemName: Icon.checkmark).font(.system(size: 11, weight: .bold)).foregroundStyle(item.key == "yellow" ? Color(hex: 0x232823) : .white) } }
                            Text(L(item.name)).font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(chosenColor == item.key ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(L(item.name))色标注")
                    .accessibilityAddTraits(chosenColor == item.key ? .isSelected : [])
                }
            }
            IndexRule()
            IndexHeading(title: Text("标注样式"))
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.space1)) : AnyLayout(HStackLayout(spacing: Theme.space1))) {
                ForEach([("background", "浅底", Icon.highlight), ("underline", "直线", Icon.underlineStyle), ("wavy", "波浪线", Icon.wavyStyle)], id: \.0) { style, title, icon in
                    Button {
                        chosenStyle = style
                        lastStyle = style
                    } label: {
                        IndexActionLabel(title: LocalizedStringKey(title), symbol: icon).font(.caption.weight(.medium))
                            .foregroundStyle(chosenStyle == style ? accent : tint)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(chosenStyle == style ? accent.opacity(0.14) : tint.opacity(0.05), in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosenStyle == style ? .isSelected : [])
                }
            }
            action(existing == nil ? "添加标注" : "保存标注", Icon.checkmark, { onMark(chosenColor, chosenStyle) }, prominent: true)
            if existing != nil {
                Button("删除这条标注…") { removing = true }
                    .font(.caption).foregroundStyle(IndexTheme.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
            }
        }
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void, prominent: Bool = false) -> some View {
        Button(action: run) {
            IndexActionLabel(title: LocalizedStringKey(title), symbol: icon)
        }
        .buttonStyle(IndexActionStyle(role: prominent ? .primary : .secondary, expands: true))
    }
}

// MARK: - 笔记编辑

struct NoteEditor: View {
    let quote: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            IndexPage {
                VStack(alignment: .leading, spacing: Theme.space2) {
                    IndexHeading(title: Text("选中的原文"))
                    Text(verbatim: quote)
                        .font(IndexTheme.editorial(19, relativeTo: .body))
                        .foregroundStyle(IndexTheme.ink).lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.space4)
                .indexPanel(fill: IndexTheme.wash)

                VStack(alignment: .leading, spacing: Theme.space2) {
                    IndexHeading(title: Text("我的想法")).accessibilityHidden(true)
                    TextEditor(text: $text)
                        .font(.body).foregroundStyle(IndexTheme.ink)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .padding(Theme.space2).frame(minHeight: 180)
                        .background(IndexTheme.surface, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: IndexTheme.controlRadius)
                                .strokeBorder(focused ? IndexTheme.accent : IndexTheme.edge, lineWidth: Theme.rule)
                                .allowsHitTesting(false)
                        }
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("写一点你的想法").foregroundStyle(IndexTheme.muted)
                                    .padding(.horizontal, Theme.space3).padding(.vertical, Theme.space4)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel("我的想法")
                }
                Button("保存笔记", action: save).buttonStyle(IndexActionStyle(role: .primary, expands: true))
                Button("取消") { dismiss() }.buttonStyle(IndexActionStyle(role: .plain, expands: true))
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold) }
            }
            .onAppear { focused = true }
        }
        .tint(IndexTheme.accent)
        .presentationDetents([.large])
    }
    private func save() { onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }

}

// MARK: - 书摘列表

/// 一本书的划线与笔记，按章节顺序；轻点跳到原文。
struct NotesList: View {
    let entryID: String
    var chapterTitle: (Int) -> String = { "第 \($0 + 1) 章" }
    var query = ""
    var unresolvedIDs: Set<UUID> = []
    let onJump: (Highlight) -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing: Highlight?
    @State private var removing: Highlight?
    private var bookTitle: String { model.entries.first { $0.id == entryID }?.title ?? "" }
    private var bookAuthor: String { model.entries.first { $0.id == entryID }?.author ?? "" }
    private var notes: [Highlight] {
        (model.entries.first { $0.id == entryID }?.notes ?? []).filter {
            query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || ($0.note ?? "").localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        Group {
            if notes.isEmpty {
                IndexStatus(kind: .empty, title: Text("还没有摘记"),
                            detail: Text("长按正文添加标注或写笔记。你的原文与想法会一起收在这里。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 8) {
                    Button { onJump(note) } label: { NoteRow(note: note, chapter: chapterTitle(note.chapter)) }
                        .buttonStyle(.plain)
                    if unresolvedIDs.contains(note.id) {
                        Text("尚未定位 · 原文与笔记已保留").font(.caption).foregroundStyle(IndexTheme.warning)
                    }
                    IndexRule()
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 14))) {
                        Button { onJump(note) } label: { Label("回到原文", systemImage: Icon.read).frame(minHeight: 44) }
                        Button { editing = note } label: { Label(note.note == nil ? "写笔记" : "编辑笔记", systemImage: Icon.note).frame(minHeight: 44) }
                        Spacer(minLength: 0)
                        Menu {
                            Section("引用") {
                                Button { UIPasteboard.general.string = note.text } label: { Label("复制原文", systemImage: Icon.copy) }
                                ShareLink(item: note.text) { Label("分享原文", systemImage: Icon.share) }
                                QuoteShareLink(text: note.text, title: bookTitle, author: bookAuthor, chapter: chapterTitle(note.chapter)) {
                                    Label("分享摘句卡片", systemImage: Icon.quote)
                                }
                            }
                            Section {
                                Button(role: .destructive) { removing = note } label: { Label("删除标注…", systemImage: Icon.delete) }
                            }
                        } label: { Label("更多", systemImage: Icon.more).frame(minHeight: 44) }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(IndexTheme.accent)
                    .frame(minHeight: 44)
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 10)
                .listRowBackground(IndexTheme.surface)
                .swipeActions(allowsFullSwipe: false) {
                    Button(role: .destructive) { removing = note } label: { Label("删除", systemImage: Icon.delete) }
                    Button { editing = note } label: { Label("笔记", systemImage: Icon.note) }.tint(IndexTheme.accent)
                }
                .contextMenu {
                    Button { onJump(note) } label: { Label("回到原文", systemImage: Icon.read) }
                    Button { editing = note } label: { Label(note.note == nil ? "写笔记" : "编辑笔记", systemImage: Icon.note) }
                    Button { UIPasteboard.general.string = note.text } label: { Label("复制原文", systemImage: Icon.copy) }
                    Button(role: .destructive) { removing = note } label: { Label("删除标注…", systemImage: Icon.delete) }
                }
            }
        }
        .sheet(item: $editing) { note in
            NoteEditor(quote: note.text, text: note.note ?? "") { text in
                var next = note; next.note = text.isEmpty ? nil : text
                model.updateHighlight(entryID, next)
            }
        }
        .confirmationDialog("删除这条标注？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { note in
            Button("删除标注与附带笔记", role: .destructive) {
                model.removeHighlight(entryID, id: note.id)
                removing = nil
            }
            Button("取消", role: .cancel) { removing = nil }
        } message: { _ in Text("只删除这条标注及其笔记，书中原文不会改变。") }
    }
}

struct NoteRow: View {
    let note: Highlight
    let chapter: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.space1))
            : AnyLayout(HStackLayout(spacing: Theme.space2))
        VStack(alignment: .leading, spacing: Theme.space2) {
            layout {
                Text(verbatim: chapter).frame(maxWidth: .infinity, alignment: .leading)
                Text(note.date, format: .dateTime.year().month().day())
            }
            .font(.caption).foregroundStyle(IndexTheme.muted)
            Text(verbatim: note.text)
                .font(IndexTheme.editorial(17, relativeTo: .body)).lineSpacing(5)
                .foregroundStyle(IndexTheme.ink).lineLimit(typeSize.isAccessibilitySize ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Theme.space3)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(ReaderMark.color(note.color))
                        .frame(width: Theme.ruleMedium).allowsHitTesting(false).accessibilityHidden(true)
                }
            if let text = note.note {
                Text(verbatim: text).font(.subheadline).foregroundStyle(IndexTheme.ink)
                    .padding(Theme.space2).frame(maxWidth: .infinity, alignment: .leading)
                    .background(IndexTheme.wash, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
            }
        }
        .padding(.vertical, Theme.space1)
        .contentShape(Rectangle())
    }
}

/// 全部书摘：按书分组（「设置」→ 阅读资料）。
struct AllNotesView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    private var books: [ShelfEntry] { model.visibleEntries.filter { !$0.notes.isEmpty } }
    var body: some View {
        List {
            if books.isEmpty {
                ContentUnavailableView("还没有书摘", systemImage: Icon.highlight, description: Text("阅读时长按正文，添加标注或写一条笔记。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(books) { entry in
                let notes = entry.notes.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || ($0.note ?? "").localizedCaseInsensitiveContains(query) }
                if !notes.isEmpty {
                    Section {
                        NotesList(entryID: entry.id, query: query) { note in
                            model.open(entry, target: .init(note))
                        }
                    } header: {
                        HStack(spacing: 8) {
                            BookCoverView(title: entry.title, color: entry.color, image: model.covers[entry.id], width: 24)
                            Text(entry.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).textCase(nil)
                            SealBadge(text: "\(notes.count) 条", color: Theme.gold, background: Theme.goldSoft)
                            Spacer()
                            ShareLink(item: Self.markdown(entry)) { Label("导出", systemImage: Icon.share).font(.caption.weight(.medium)).foregroundStyle(Theme.accent).frame(minHeight: 44) }
                                .accessibilityLabel("导出《\(entry.title)》书摘")
                        }
                    }
                }
            }
        }
        .navigationTitle("书摘与笔记")
        .searchable(text: $query, prompt: "搜索划线与笔记")
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
    }
    /// 导出为 Markdown 文本
    static func markdown(_ entry: ShelfEntry) -> String {
        var lines = ["# 《\(entry.title)》书摘", "", "\(entry.author)", ""]
        for note in entry.notes {
            lines.append("> \(note.text)")
            if let text = note.note { lines.append(""); lines.append(text) }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
