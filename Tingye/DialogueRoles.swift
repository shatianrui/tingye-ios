import Foundation

// MARK: - 分角色配音（参照 PureLibro 的多角色听书）

enum DialogueRole: Equatable { case narrator, male, female }

/// 按引号和「他 / 她 / 公子 / 姑娘……说道」这类说话人提示判断一句对话的说话人性别。
/// 只适合中文小说；判断不出来时返回旁白，宁可少分也不乱分。
enum DialogueRoles {
    static let female = ["她", "姑娘", "小姐", "夫人", "公主", "皇后", "娘娘", "王妃", "丫头", "丫鬟", "仙子", "圣女", "女帝", "女子", "女人", "少女", "女孩", "妇人", "老妇", "母亲", "妈妈", "娘亲", "姐姐", "妹妹", "嫂子", "姑姑", "婶婶", "奶奶", "外婆", "妻子", "老婆", "师姐", "师妹", "师娘"]
    static let male = ["他", "公子", "少爷", "先生", "王爷", "皇上", "陛下", "老爷", "掌柜", "和尚", "道士", "老者", "老头", "男子", "男人", "少年", "男孩", "汉子", "父亲", "爸爸", "爹", "哥哥", "弟弟", "叔叔", "伯伯", "爷爷", "外公", "丈夫", "老公", "师兄", "师弟", "师父", "师傅"]
    static let verbs = ["说", "道", "问", "答", "喊", "叫", "笑", "骂", "吼", "嚷", "叹", "低声", "沉声", "冷声", "开口", "回应", "嘀咕", "喝道", "怒道"]
    private static let quotes: [(Character, Character)] = [("“", "”"), ("「", "」"), ("『", "』"), ("\"", "\"")]

    static func role(_ index: Int, in sentences: [Sentence]) -> DialogueRole {
        guard sentences.indices.contains(index) else { return .narrator }
        let text = sentences[index].text
        guard hasQuote(text) else { return .narrator }
        // 1. 同一句引号外的说话提示：「他笑道：“……”」「“……”她说。」
        if let role = attribution(outside(text)) { return role }
        // 2. 纯引语：前一句以「：」结尾（她说：），或后一句开头就是说话提示（他笑了笑。）
        if index > 0 {
            let previous = sentences[index - 1].text
            if previous.hasSuffix("：") || previous.hasSuffix(":"), let role = attribution(String(previous.suffix(16))) { return role }
        }
        if index + 1 < sentences.count {
            let next = sentences[index + 1].text
            if !hasQuote(String(next.prefix(2))), let role = attribution(String(next.prefix(10)), needsVerb: true) { return role }
        }
        return .narrator
    }

    static func hasQuote(_ text: String) -> Bool { quotes.contains { text.contains($0.0) } }

    /// 去掉引号内的话，只留叙述部分
    static func outside(_ text: String) -> String {
        var result = "", depth = 0
        for c in text {
            if quotes.contains(where: { $0.0 == c && $0.0 != $0.1 }) || (c == "\"" && depth == 0) { depth += 1; continue }
            if quotes.contains(where: { $0.1 == c && $0.0 != $0.1 }) || (c == "\"" && depth > 0) { depth = max(0, depth - 1); continue }
            if depth == 0 { result.append(c) }
        }
        return result
    }

    /// 叙述里最先出现的人称 / 称谓决定说话人（「他对她说」→ 他）；多逗句时优先取含说话动词分句中的主语（「她看着他，他笑道」→ 他）；needsVerb 时要求同时有说话动词
    static func attribution(_ narration: String, needsVerb: Bool = false) -> DialogueRole? {
        let text = narration as NSString
        guard text.length > 0 else { return nil }
        let hasVerb = verbs.contains(where: { narration.contains($0) })
        if needsVerb && !hasVerb { return nil }
        func role(in segment: NSString) -> DialogueRole? {
            func first(_ words: [String]) -> Int {
                words.map { segment.range(of: $0).location }.filter { $0 != NSNotFound }.min() ?? Int.max
            }
            let f = first(female), m = first(male)
            if f == Int.max && m == Int.max { return nil }
            return f < m ? .female : .male
        }
        if hasVerb {
            let clauses = narration.components(separatedBy: CharacterSet(charactersIn: "，,；;。！!？?"))
            for clause in clauses where verbs.contains(where: { clause.contains($0) }) {
                if let matched = role(in: clause as NSString) { return matched }
            }
        }
        return role(in: text)
    }
}

// MARK: - Azure 常用中文神经网络音色

enum AzureVoices {
    static let all: [CloudSpeech.Voice] = [
        .init(value: "zh-CN-XiaoxiaoNeural", label: "晓晓 · 女"),
        .init(value: "zh-CN-XiaoyiNeural", label: "晓伊 · 女"),
        .init(value: "zh-CN-XiaochenNeural", label: "晓辰 · 女"),
        .init(value: "zh-CN-XiaohanNeural", label: "晓涵 · 女"),
        .init(value: "zh-CN-XiaomoNeural", label: "晓墨 · 女"),
        .init(value: "zh-CN-XiaoqiuNeural", label: "晓秋 · 女"),
        .init(value: "zh-CN-XiaoruiNeural", label: "晓睿 · 女"),
        .init(value: "zh-CN-XiaoshuangNeural", label: "晓双 · 童声"),
        .init(value: "zh-CN-XiaoyanNeural", label: "晓颜 · 女"),
        .init(value: "zh-CN-XiaoyouNeural", label: "晓悠 · 童声"),
        .init(value: "zh-CN-XiaozhenNeural", label: "晓甄 · 女"),
        .init(value: "zh-CN-YunxiNeural", label: "云希 · 男"),
        .init(value: "zh-CN-YunjianNeural", label: "云健 · 男"),
        .init(value: "zh-CN-YunyangNeural", label: "云扬 · 男（播音）"),
        .init(value: "zh-CN-YunfengNeural", label: "云枫 · 男"),
        .init(value: "zh-CN-YunhaoNeural", label: "云皓 · 男"),
        .init(value: "zh-CN-YunyeNeural", label: "云野 · 男"),
        .init(value: "zh-CN-YunzeNeural", label: "云泽 · 男（老年）"),
        .init(value: "zh-TW-HsiaoChenNeural", label: "曉臻 · 女（台湾）"),
        .init(value: "zh-TW-YunJheNeural", label: "雲哲 · 男（台湾）"),
        .init(value: "zh-HK-HiuMaanNeural", label: "曉曼 · 女（粤语）"),
        .init(value: "zh-HK-WanLungNeural", label: "雲龍 · 男（粤语）"),
        .init(value: "en-US-AvaMultilingualNeural", label: "Ava · 女（多语言）"),
        .init(value: "en-US-AndrewMultilingualNeural", label: "Andrew · 男（多语言）"),
    ]
}
