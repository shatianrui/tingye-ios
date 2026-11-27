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
            Section {
                Stepper(value: $maxLength, in: 5_000...200_000, step: 5_000) {
                    Text("章节最大字数 \(maxLength)").monospacedDigit()
                }
                .accessibilityIdentifier("txt.maxLength")
                .listRowBackground(Theme.groupedCard)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.space2) {
                        ForEach([10_000, 30_000, 50_000], id: \.self) { value in
                            Chip(title: "\(value)", selected: maxLength == value) { maxLength = value }
                        }
                    }
                    .padding(.vertical, Theme.space1)
                }
                .listRowBackground(Theme.groupedCard)
            } header: { Text("TXT 分章") } footer: { Text("超过这个字数的章节会在段落处继续切分，避免整本书只有一章。") }
            Section {
                ruleRow(name: "内置规则", pattern: "", selected: active.isEmpty)
                ForEach(rules, id: \.self) { pattern in
                    ruleRow(name: pattern, pattern: pattern, selected: active == pattern)
                        .swipeActions { Button("删除", role: .destructive) { remove(pattern) } }
                }
            } header: { Text("使用中的规则") } footer: { Text("轻点选用。内置规则识别「第X章 / 回 / 卷」「Chapter N」与 Markdown 标题。") }
            Section {
                VStack(alignment: .leading, spacing: Theme.space3) {
                    TextField("例如：^\\s*第.{1,9}章.*$", text: $draft, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(Theme.space3)
                        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.radiusField))
                        .overlay { RoundedRectangle(cornerRadius: Theme.radiusField).strokeBorder(Theme.lineField, lineWidth: Theme.hairline) }
                        .accessibilityIdentifier("txt.draft")
                    if !draft.isEmpty && draftRegex == nil {
                        SealBadge(text: "正则表达式无效。", color: Theme.danger, background: Theme.dangerSoft)
                    }
                    HStack {
                        TextButton("加入并使用") { add(draft, use: true) }
                        Spacer()
                        TextButton("仅加入") { add(draft, use: false) }
                    }
                    .disabled(draftRegex == nil)
                }
                .padding(.vertical, Theme.space1)
                .listRowBackground(Theme.groupedCard)
                Menu("从预设加入") {
                    ForEach(TxtChapterRules.presets, id: \.pattern) { preset in
                        Button(preset.name) { add(preset.pattern, use: false) }
                    }
                }
                .foregroundStyle(Theme.clayDeep)
                .frame(minHeight: Theme.iconButtonSize)
                .listRowBackground(Theme.groupedCard)
            } header: { Text("添加规则") } footer: { Text("每行开头匹配到的文字作为章节标题。错误的规则可能导致章节错乱，可随时换回内置规则。") }
            Section {
                TextField("粘贴一段原文试试", text: $sample, axis: .vertical)
                    .lineLimit(3...8)
                    .listRowBackground(Theme.groupedCard)
                ForEach(Array(previewTitles.enumerated()), id: \.offset) { index, title in
                    HStack(spacing: Theme.space3) {
                        Text(String(format: "%02d", index + 1)).font(Theme.sans(14)).foregroundStyle(Theme.ink3).monospacedDigit()
                        Text(title).font(Theme.serif(17)).lineLimit(1)
                    }
                    .listRowBackground(Theme.groupedCard)
                }
            } header: { Text("预览（\(previewTitles.count) 章）") }
        }
        .tint(Theme.clayDeep).foregroundStyle(Theme.ink)
        .editorialList()
        .groupedBackground()
        .navigationTitle("TXT 分章规则").navigationBarTitleDisplayMode(.inline)
    }

    private func ruleRow(name: String, pattern: String, selected: Bool) -> some View {
        Button { active = pattern } label: {
            HStack {
                Text(name).font(pattern.isEmpty ? .body : .system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.ink).lineLimit(2)
                Spacer()
                if selected { ThemeIcon(symbol: Icon.checkmark, size: 18).foregroundStyle(Theme.clayDeep) }
            }
            .frame(minHeight: Theme.iconButtonSize).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.groupedCard)
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
