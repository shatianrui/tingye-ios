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
            IndexHeading(title: Text("选中文字后的面板"),
                         detail: Text("拖动调整顺序，排在最前且显示的分组会默认打开。至少保留一个分组。"))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section {
                ForEach(order) { tool in
                    Toggle(isOn: Binding(get: { !hidden.contains(tool.rawValue) }, set: { show in
                        if show { hidden.remove(tool.rawValue) }
                        else if order.count - hidden.count > 1 { hidden.insert(tool.rawValue) }
                        save()
                    })) {
                        IndexRowLabel(title: Text(L(tool.rawValue)),
                                      detail: tool == SelectionTool.visible(order: order, hidden: hidden).first ? Text("默认") : nil)
                    }
                    .accessibilityIdentifier("menu.tool.\(tool.rawValue)")
                    .listRowBackground(IndexTheme.surface)
                }
                .onMove { from, to in order.move(fromOffsets: from, toOffset: to); save() }
            }
            Button("恢复默认") { order = SelectionTool.allCases; hidden = []; save() }
                .buttonStyle(IndexActionStyle(role: .secondary))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .environment(\.editMode, .constant(.active))
        .indexList()
        .navigationTitle("菜单")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: SelectionTool.orderKey)
        UserDefaults.standard.set(Array(hidden), forKey: SelectionTool.hiddenKey)
    }
}
