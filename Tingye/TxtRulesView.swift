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
        Form {
            Section {
                Stepper(value: $maxLength, in: 5_000...200_000, step: 5_000) {
                    HStack { Text("章节最大字数"); Spacer(); Text("\(maxLength)").monospacedDigit().foregroundStyle(Theme.ink3) }
                }
                .accessibilityIdentifier("txt.maxLength")
            } header: { Text("TXT 分章") } footer: { Text("超过这个字数的章节会在段落处继续切分，避免整本书只有一章。") }
            .listRowBackground(Theme.surface)

            Section {
                ruleRow(name: "内置规则", pattern: "", selected: active.isEmpty)
                ForEach(rules, id: \.self) { pattern in
                    ruleRow(name: pattern, pattern: pattern, selected: active == pattern)
                        .swipeActions { Button("删除", role: .destructive) { remove(pattern) } }
                }
            } header: { Text("使用中的规则") } footer: { Text("轻点选用。内置规则识别「第X章 / 回 / 卷」「Chapter N」与 Markdown 标题。") }
            .listRowBackground(Theme.surface)

            Section {
                TextField("例如：^\\s*第.{1,9}章.*$", text: $draft, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("txt.draft")
                if !draft.isEmpty && draftRegex == nil {
                    Text("正则表达式无效。").font(.footnote).foregroundStyle(Theme.danger)
                }
                HStack {
                    Button("加入并使用") { add(draft, use: true) }
                    Spacer()
                    Button("仅加入") { add(draft, use: false) }
                }
                .disabled(draftRegex == nil)
                Menu("从预设加入") {
                    ForEach(TxtChapterRules.presets, id: \.pattern) { preset in
                        Button(preset.name) { add(preset.pattern, use: false) }
                    }
                }
            } header: { Text("添加规则") } footer: { Text("每行开头匹配到的文字作为章节标题。错误的规则可能导致章节错乱，可随时换回内置规则。") }
            .listRowBackground(Theme.surface)

            Section {
                TextField("粘贴一段原文试试", text: $sample, axis: .vertical).lineLimit(3...8)
                ForEach(Array(previewTitles.enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent).monospacedDigit()
                        Text(title).lineLimit(1)
                    }
                }
            } header: { Text("预览（\(previewTitles.count) 章）") }
            .listRowBackground(Theme.surface)
        }
        .tint(Theme.accent)
        .foregroundStyle(Theme.ink)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("TXT 分章规则")
        .navigationBarTitleDisplayMode(.large)
    }

    private func ruleRow(name: String, pattern: String, selected: Bool) -> some View {
        Button { active = pattern } label: {
            HStack {
                Text(name).font(pattern.isEmpty ? .body : .system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.ink).lineLimit(2)
                Spacer()
                if selected { Image(systemName: Icon.checkmark).foregroundStyle(Theme.accent) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
