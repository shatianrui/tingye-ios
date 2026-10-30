import SwiftUI

/// 选中文字后的操作面板分组：顺序与显示可在「菜单」里自定义，第一项为默认打开的分组。
enum SelectionTool: String, CaseIterable, Hashable, Identifiable {
    case mark = "标注", note = "笔记", quote = "引用"
    var id: String { rawValue }
    static let orderKey = "selection.tools.order"
    static let hiddenKey = "selection.tools.hidden"

    /// 保存的顺序（缺失的新分组补在末尾）。
    static func ordered(_ saved: [String]? = UserDefaults.standard.stringArray(forKey: orderKey)) -> [SelectionTool] {
        let known = (saved ?? []).compactMap(SelectionTool.init(rawValue:))
        var seen = Set<SelectionTool>(), result: [SelectionTool] = []
        for tool in known + allCases where seen.insert(tool).inserted { result.append(tool) }
        return result
    }
    /// 实际显示的分组：按顺序去掉隐藏项；全部隐藏时退回全部显示，面板不会变空。
    static func visible(order: [SelectionTool] = ordered(), hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])) -> [SelectionTool] {
        let shown = order.filter { !hidden.contains($0.rawValue) }
        return shown.isEmpty ? order : shown
    }
}

/// 菜单：自定义选中文字面板的分组顺序与显示。
struct MenuSettingsView: View {
    @State private var order = SelectionTool.ordered()
    @State private var hidden = Set(UserDefaults.standard.stringArray(forKey: SelectionTool.hiddenKey) ?? [])

    var body: some View {
        List {
            Section {
                ForEach(order) { tool in
                    Toggle(isOn: Binding(get: { !hidden.contains(tool.rawValue) }, set: { show in
                        if show { hidden.remove(tool.rawValue) }
                        else if order.count - hidden.count > 1 { hidden.insert(tool.rawValue) }
                        save()
                    })) {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", (order.firstIndex(of: tool) ?? 0) + 1)).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent).monospacedDigit()
                            Text(tool.rawValue)
                            if tool == SelectionTool.visible(order: order, hidden: hidden).first {
                                Text("默认").font(.caption2.weight(.medium)).foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.accentSoft, in: Capsule())
                            }
                        }
                    }
                    .tint(Theme.accent)
                    .accessibilityIdentifier("menu.tool.\(tool.rawValue)")
                }
                .onMove { from, to in order.move(fromOffsets: from, toOffset: to); save() }
            } header: { Text("选中文字后的面板") } footer: { Text("拖动调整顺序，排在最前且显示的分组会默认打开。至少保留一个分组。") }
            .listRowBackground(Theme.surface)
            Section {
                Button("恢复默认") { order = SelectionTool.allCases; hidden = []; save() }
            }
            .listRowBackground(Theme.surface)
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("菜单")
        .navigationBarTitleDisplayMode(.large)
    }

    private func save() {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: SelectionTool.orderKey)
        UserDefaults.standard.set(Array(hidden), forKey: SelectionTool.hiddenKey)
    }
}
