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
        ("clay", "陶土", 0xD97757), ("ink", "墨", 0x191817), ("gray", "灰", 0x6B6960),
    ]
    /// 仅映射显示，不改写旧标注的存储键或坐标。
    static func toneKey(_ key: String) -> String {
        switch key {
        case "ink", "blue", "purple": return "ink"
        case "gray", "green": return "gray"
        default: return "clay"
        }
    }
    static func uiColor(_ key: String) -> UIColor {
        switch toneKey(key) {
        case "ink": return UIColor(Theme.ink)
        case "gray": return UIColor(Theme.ink3)
        default: return UIColor(Theme.clay)
        }
    }
    static func newColor(_ stored: String?) -> String { toneKey(stored ?? "clay") }
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
    var paper: Color = Theme.surface
    var accent: Color = Theme.accent
    let onMark: (_ color: String, _ style: String) -> Void
    let onRemove: () -> Void
    let onNote: () -> Void
    let onListen: () -> Void
    let onCopy: () -> Void
    let onExtend: (_ delta: Int) -> Void
    let onClose: () -> Void
    @AppStorage("highlight.lastColor") private var lastColor = "clay"
    @AppStorage("highlight.lastStyle") private var lastStyle = "background"

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
                Text("选段与标注").font(Theme.serif(20)).accessibilityAddTraits(.isHeader)
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
                Button(action: onClose) {
                    ThemeIcon(symbol: Icon.close, size: 20)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("取消选择")
            }
            .buttonStyle(.plain)
            Text(text)
                .font(Theme.serif(18, relativeTo: .body)).lineLimit(4).lineSpacing(7)
                .padding(Theme.space4).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.radius))
            SegmentedBar(options: tools, selection: tool, title: { $0.rawValue }, onSelect: { tool = $0 })
            Group {
                switch tool {
                case .mark: markTools
                case .note:
                    VStack(alignment: .leading, spacing: Theme.space3) {
                        if let note = existing?.note, !note.isEmpty {
                            Text(note).font(.subheadline).lineLimit(3).foregroundStyle(Theme.ink3)
                        } else {
                            Text("给这段文字，留一点自己的想法。")
                                .font(.subheadline).foregroundStyle(Theme.ink3)
                        }
                        action(existing?.note == nil ? "写笔记" : "编辑笔记", Icon.note, onNote, prominent: true)
                    }
                case .quote:
                    VStack(spacing: Theme.space2) {
                        HStack(spacing: 10) {
                            action("复制原文", Icon.copy, onCopy)
                            ShareLink(item: text) {
                                Label("分享选段", systemImage: Icon.share)
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                            }
                            .buttonStyle(.plain)
                        }
                        action("从这里开始听", Icon.listen, onListen)
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.space4)
        .padding(.top, Theme.space2)
        .padding(.bottom, Theme.space4)
        .frame(maxWidth: 520)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
        .floatingPanel()
    }

    private var markTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.space1) {
                ForEach(ReaderMark.palette, id: \.key) { item in
                    Button {
                        chosenColor = item.key
                        lastColor = item.key
                    } label: {
                        VStack(spacing: Theme.space1) {
                            ZStack {
                                if item.key == "clay" { Circle().fill(ReaderMark.color(item.key)) }
                                else if item.key == "ink" { RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(ReaderMark.color(item.key)) }
                                else { Capsule().strokeBorder(ReaderMark.color(item.key), lineWidth: Theme.ruleMedium) }
                                if ReaderMark.toneKey(chosenColor) == item.key {
                                    ThemeIcon(symbol: Icon.checkmark, size: 13)
                                        .foregroundStyle(item.key == "clay" ? Theme.onClay : (item.key == "ink" ? Theme.bg : Theme.ink))
                                }
                            }
                            .frame(width: Theme.space5, height: Theme.space5)
                            Text(item.name).font(.caption2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(ReaderMark.toneKey(chosenColor) == item.key ? Theme.claySoft : .clear, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name)色标注")
                    .accessibilityAddTraits(ReaderMark.toneKey(chosenColor) == item.key ? .isSelected : [])
                }
            }
            SegmentedBar(options: ["background", "underline", "wavy"], selection: chosenStyle,
                         title: { ["background": "浅底", "underline": "直线", "wavy": "波浪线"][$0] ?? $0 },
                         onSelect: { chosenStyle = $0; lastStyle = $0 })
            action(existing == nil ? "添加标注" : "保存标注", Icon.checkmark, { onMark(chosenColor, chosenStyle) }, prominent: true)
            if existing != nil {
                Button("删除这条标注…") { removing = true }
                    .font(.caption).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
            }
        }
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void, prominent: Bool = false) -> some View {
        Button(action: run) {
            HStack(spacing: Theme.space2) {
                ThemeIcon(symbol: icon, size: 20)
                Text(L(title))
            }
                .font(.body.weight(.medium))
                .foregroundStyle(prominent ? Theme.bg : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(prominent ? Theme.ink : Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EditorialIntro(title: "把想法留在这里", detail: "原文与笔记分别保存，随时可以修改笔记。")
                    Text("选中的原文").font(.caption.weight(.semibold)).foregroundStyle(Theme.ink2)
                    Text(quote)
                        .font(Theme.serif(19, relativeTo: .body))
                        .foregroundStyle(Theme.ink).lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true).padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warm, in: RoundedRectangle(cornerRadius: Theme.heroRadius))
                    Text("我的想法").font(.caption).foregroundStyle(Theme.ink3)
                    TextEditor(text: $text)
                        .font(.body).foregroundStyle(Theme.ink)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .padding(10).frame(minHeight: 180)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty { Text("写一点你的想法").foregroundStyle(Theme.ink3).padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false) }
                        }
                        .accessibilityLabel("我的想法")
                    Button("保存笔记", action: save).buttonStyle(PrimaryButtonStyle(height: 50))
                    Button("取消") { dismiss() }.buttonStyle(SecondaryButtonStyle(height: 50))
                }
                .padding(24)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg)
            .navigationTitle("笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold) }
            }
            .onAppear { focused = true }
        }
        .tint(Theme.accent)
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
                EditorialNotice(title: "还没有摘记", detail: "长按正文添加标注或写笔记。你的原文与想法会一起收在这里。")
                    .listRowBackground(Color.clear)
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 8) {
                    Button { onJump(note) } label: { NoteRow(note: note, chapter: chapterTitle(note.chapter)) }
                        .buttonStyle(.plain)
                    if unresolvedIDs.contains(note.id) { Text("尚未定位 · 原文与笔记已保留").font(.caption).foregroundStyle(Theme.ink3) }
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
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 10)
                .listRowBackground(Theme.surface)
                .swipeActions(allowsFullSwipe: false) {
                    Button(role: .destructive) { removing = note } label: { Label("删除", systemImage: Icon.delete) }
                    Button { editing = note } label: { Label("笔记", systemImage: Icon.note) }.tint(Theme.accent)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(ReaderMark.color(note.color)).frame(width: 7, height: 7)
                Text(chapter).lineLimit(1)
                Spacer()
                Text(note.date.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption2)
            .foregroundStyle(Theme.ink3)
            Text(note.text)
                .font(Theme.serif(17, relativeTo: .body))
                .lineSpacing(6)
                .foregroundStyle(Theme.ink)
                .lineLimit(5)
                .padding(.leading, 11)
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1.5).fill(ReaderMark.color(note.color)).frame(width: 2.5) }
            if let text = note.note {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 5)
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
