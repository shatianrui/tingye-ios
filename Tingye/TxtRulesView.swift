import SwiftUI

/// TXT 分章规则：自定义正则、章节最大字数、预览命中的标题。
/// 只影响之后导入或在书籍详情里「重新分章」的 TXT，不会改动其他书籍。
struct TxtRulesView: View {
    @AppStorage(TxtChapterRules.activeKey) private var active = ""
    @AppStorage(TxtChapterRules.maxLengthKey) private var maxLength = TxtChapterRules.defaultMaxLength
    @State private var rules = TxtChapterRules.rules
    @State private var draft = ""
    @State private var sample = "序\n第一章 山水\n春风又绿江南岸。\n第二章 归人\n明月何时照我还。"

    private var draftRegex: NSRegularExpression? { TxtChapterRules.compile(draft) }
    private var previewTitles: [String] {
        let regex = draftRegex ?? TxtChapterRules.compile(active)
        return BookImporter.splitText(sample, title: "示例", rule: regex, maxLength: maxLength).map(\.title)
    }

    var body: some View {
        List {
            IndexHeading(title: Text("TXT 分章规则"), detail: Text("先用一段原文预览，再将规则用于导入或重新分章。"))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section {
                Stepper(value: $maxLength, in: 5_000...200_000, step: 5_000) {
                    Text("章节最大字数 \(maxLength)").monospacedDigit()
                }
                .accessibilityIdentifier("txt.maxLength")
                IndexScopePicker(options: [10_000, 30_000, 50_000], selection: maxLength,
                                 title: { Text($0, format: .number) }, onSelect: { maxLength = $0 })
            } header: { Text("TXT 分章") } footer: { Text("超过这个字数的章节会在段落处继续切分，避免整本书只有一章。") }
            .listRowBackground(IndexTheme.surface)

            Section {
                ruleRow(name: L("内置规则"), pattern: "", selected: active.isEmpty)
                ForEach(rules, id: \.self) { pattern in
                    ruleRow(name: pattern, pattern: pattern, selected: active == pattern)
                        .swipeActions { Button("删除", role: .destructive) { remove(pattern) } }
                }
            } header: { Text("使用中的规则") } footer: { Text("轻点选用。内置规则识别「第X章 / 回 / 卷」「Chapter N」与 Markdown 标题。") }
            .listRowBackground(IndexTheme.surface)

            Section {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    TextField("例如：^\\s*第.{1,9}章.*$", text: $draft, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(Theme.space3)
                        .background(IndexTheme.canvas, in: RoundedRectangle(cornerRadius: IndexTheme.controlRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: IndexTheme.controlRadius)
                                .strokeBorder(IndexTheme.edge, lineWidth: Theme.rule).allowsHitTesting(false)
                        }
                        .accessibilityIdentifier("txt.draft")
                    if !draft.isEmpty && draftRegex == nil {
                        IndexStatus(kind: .failure, title: Text("正则表达式无效。"))
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.space2) { addActions }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: Theme.space2) { addActions }
                    }
                    .disabled(draftRegex == nil)
                    Menu("从预设加入") {
                        ForEach(TxtChapterRules.presets, id: \.pattern) { preset in
                            Button(L(preset.name)) { add(preset.pattern, use: false) }
                        }
                    }
                    .frame(minHeight: Theme.iconButtonSize)
                }
                .padding(.vertical, Theme.space2)
            } header: { Text("添加规则") } footer: { Text("每行开头匹配到的文字作为章节标题。错误的规则可能导致章节错乱，可随时换回内置规则。") }
            .listRowBackground(IndexTheme.surface)

            Section {
                TextField("粘贴一段原文试试", text: $sample, axis: .vertical).lineLimit(3...8)
                    .padding(.vertical, Theme.space2)
                ForEach(Array(previewTitles.enumerated()), id: \.offset) { index, title in
                    IndexRowLabel(title: Text(verbatim: title), detail: Text("第 \(index + 1) 章"))
                }
            } header: { Text("预览（\(previewTitles.count) 章）") }
            .listRowBackground(IndexTheme.surface)
        }
        .indexList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("TXT 分章规则").navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var addActions: some View {
        Button("加入并使用") { add(draft, use: true) }.buttonStyle(IndexActionStyle(role: .primary))
        Button("仅加入") { add(draft, use: false) }.buttonStyle(IndexActionStyle(role: .secondary))
    }

    private func ruleRow(name: String, pattern: String, selected: Bool) -> some View {
        Button { active = pattern } label: {
            IndexRowLabel(title: Text(verbatim: name), detail: selected ? Text("当前规则") : nil,
                          symbol: selected ? Icon.checkmark : nil)
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func add(_ pattern: String, use: Bool) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TxtChapterRules.compile(trimmed) != nil else { return }
        if !rules.contains(trimmed) { rules.append(trimmed); TxtChapterRules.rules = rules }
        if use { active = trimmed }
        draft = ""
    }
    private func remove(_ pattern: String) {
        rules.removeAll { $0 == pattern }; TxtChapterRules.rules = rules
        if active == pattern { active = "" }
    }
}
