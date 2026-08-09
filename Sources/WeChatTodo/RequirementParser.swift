import Foundation

/// 从微信聊天截图 OCR 文本中，用规则解析出需求产生时间与相关需求
struct RequirementParser {
    static let shared = RequirementParser()

    // 需要过滤的系统提示行
    private static let systemLineRegexes: [String] = [
        "^以上是本次聊天记录",
        "^你已添加了",
        "^消息已发出，但被对方拒收了",
        "撤回了一条消息",
        "拍了拍",
        "^收到一条语音",
        "^微信安全提醒",
        "^当前聊天状态",
        "^.*\\[.*表情.*\\].*$",
        "^群聊的聊天记录",
    ]

    // 需求关键词：命中这些词的消息行视为"相关需求"
    private static let requirementKeywords: [String] = [
        "需要", "要求", "麻烦", "帮", "安排", "整理", "统计", "确认", "补充",
        "修改", "做一下", "处理", "提交", "回复", "对接", "评审", "定一下",
        "发我", "给我", "发一份", "排一下", "排期", "跟进", "跟踪", "输出",
        "汇总", "检查", "核对", "制定", "准备", "更新", "通知", "联系", "转给",
    ]

    // MARK: - 时间 token

    private enum Period: String {
        case morning = "上午", noon = "中午", afternoon = "下午", evening = "晚上", night = "凌晨"
    }

    private struct TimeToken {
        var year: Int?
        var month: Int?
        var day: Int?
        /// -2 前天 / -1 昨天 / 0 今天 / 1 明天
        var relativeDay: Int?
        /// 周几（1=周日 … 7=周六）
        var weekday: Int?
        var hour: Int?
        var minute: Int?
        var period: Period?

        /// 是否算一条时间戳行
        var isTimestampLine: Bool { year != nil || month != nil || day != nil || relativeDay != nil || weekday != nil || hour != nil }
    }

    private static let yearRegex = try! NSRegularExpression(pattern: "20\\d{2}年")
    private static let monthRegex = try! NSRegularExpression(pattern: "(\\d{1,2})月")
    private static let dayRegex = try! NSRegularExpression(pattern: "(\\d{1,2})[日号]")
    private static let hourRegex = try! NSRegularExpression(pattern: "(\\d{1,2})\\s*[点时:]")
    private static let minuteRegex = try! NSRegularExpression(pattern: "(\\d{1,2})\\s*分")
    private static let clockRegex = try! NSRegularExpression(pattern: "[点时:](\\d{1,2})")
    // 钉钉/飞书等样式：2026-08-04、2026/8/4
    private static let slashDateRegex = try! NSRegularExpression(pattern: "(20\\d{2})[/.\\-](\\d{1,2})[/.\\-](\\d{1,2})")
    // 短日期：8-04、8/4
    private static let shortDateRegex = try! NSRegularExpression(pattern: "(\\d{1,2})[/.\\-](\\d{1,2})")
    // 周几：周四 / 星期天
    private static let weekdayRegex = try! NSRegularExpression(pattern: "(周|星期)([一二三四五六日天])")
    // 对方账号名：消息前缀"张伟：" 或 "张伟：内容"
    private static let namePrefixRegex = try! NSRegularExpression(pattern: "^([\\p{Han}a-zA-Z0-9_\\-]{1,16})[:：]")
    // 系统消息中的名字：xx邀请你加入群聊 / xx撤回了一条消息 等
    private static let systemNameRegex = try! NSRegularExpression(pattern: "^([\\p{Han}a-zA-Z0-9_\\-]{1,16})(邀请你加入群聊|添加你为好友|通过你的好友申请|撤回了一条消息|拍了拍)")
    // 误识别为名字的常见词
    private static let nameBlacklist: Set<String> = [
        "备注", "昵称", "地区", "个性签名", "性别", "标签", "描述", "群聊", "我", "对方",
        "文件传输助手", "服务通知", "微信团队", "语音", "图片", "视频", "位置", "收到",
    ]

    // MARK: - 入口

    /// 解析 OCR 行序列，返回结构化待办
    func parse(lines: [OCRService.Line], now: Date = Date()) -> ParsedResult {
        let calendar = Calendar.current
        var result = ParsedResult()

        // 1) 分离时间戳行与内容行，同时按出现顺序计算"最后一条消息时间"
        var contentLines: [(text: String, index: Int)] = []
        var lastTimestamp: Date?
        var currentDateContext: Date? // 最近的日期上下文（如"8月1日"后跟"下午 3:20"）
        var seen = Set<String>()
        // 账号名候选统计（消息前缀"张伟："、系统消息"xx邀请你加入群聊"）
        var nameCounts: [String: Int] = [:]
        var nameOrder: [String] = []

        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let token = Self.parseTimeToken(text) {
                if let date = Self.resolve(token: token, now: now, calendar: calendar) {
                    // 只有日期上下文时先记下；有具体时间则覆盖当前时间戳
                    if token.hour != nil {
                        lastTimestamp = date
                        if token.year == nil && token.month == nil && token.day == nil && token.relativeDay == nil {
                            // 纯时刻行：用最近的日期上下文合并
                            if let ctx = currentDateContext {
                                lastTimestamp = Self.mergeTime(date, into: ctx, calendar: calendar)
                            }
                        } else {
                            currentDateContext = date
                        }
                    } else {
                        currentDateContext = date
                    }
                }
                continue // 时间戳行不作为内容
            }

            guard Self.isMeaningfulContent(text) else { continue }
            guard !seen.contains(text) else { continue }
            seen.insert(text)
            contentLines.append((text, contentLines.count))

            // 收集账号名候选
            if let name = Self.extractName(from: text) {
                let count = (nameCounts[name] ?? 0) + 1
                nameCounts[name] = count
                if !nameOrder.contains(name) { nameOrder.append(name) }
            }
        }

        // 2) 需求产生时间：最后一条消息时间；无时间戳则用当前时间
        result.createdAt = lastTimestamp ?? currentDateContext ?? now

        // 2.5) 对方账号名：出现次数最多者优先，平票取先出现者
        if let top = nameCounts.max(by: { $0.value < $1.value }), top.value > 0 {
            result.accountName = top.key
        }

        // 3) 内容 → 主题 / 详情 / 相关需求
        result.detail = contentLines.map(\.text).joined(separator: "\n")

        let candidates = contentLines.map(\.text)
        let related = Self.makeRelatedItems(from: candidates)
        result.relatedItems = related
        result.summary = Self.makeSummary(from: candidates, related: related) ?? "聊天待办"
        return result
    }

    // MARK: - 时间解析

    private static func parseTimeToken(_ text: String) -> TimeToken? {
        let ns = text as NSString
        var token = TimeToken()

        // 年
        if let m = yearRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            token.year = Int(ns.substring(with: m.range).replacingOccurrences(of: "年", with: ""))
        }
        // 月
        if let m = monthRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            token.month = Int(ns.substring(with: m.range(at: 1)))
        }
        // 日
        if let m = dayRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            token.day = Int(ns.substring(with: m.range(at: 1)))
        }
        // 相对日期
        if text.contains("前天") { token.relativeDay = -2 }
        else if text.contains("昨天") { token.relativeDay = -1 }
        else if text.contains("今天") { token.relativeDay = 0 }
        else if text.contains("明天") { token.relativeDay = 1 }

        // 分隔符日期：2026-08-04 / 8-04（完整日期优先，避免短日期匹配到年份后半段）
        if let m = slashDateRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            token.year = Int(ns.substring(with: m.range(at: 1)))
            token.month = Int(ns.substring(with: m.range(at: 2)))
            token.day = Int(ns.substring(with: m.range(at: 3)))
        } else if let m = shortDateRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            token.month = Int(ns.substring(with: m.range(at: 1)))
            token.day = Int(ns.substring(with: m.range(at: 2)))
        }

        // 周几
        if let m = weekdayRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let map: [String: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]
            token.weekday = map[ns.substring(with: m.range(at: 2))]
        }

        // 时段
        if text.contains("上午") { token.period = .morning }
        else if text.contains("中午") { token.period = .noon }
        else if text.contains("下午") { token.period = .afternoon }
        else if text.contains("晚上") { token.period = .evening }
        else if text.contains("凌晨") { token.period = .night }

        // 时刻
        if let m = hourRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            token.hour = Int(ns.substring(with: m.range(at: 1)))
            if let cm = clockRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                token.minute = Int(ns.substring(with: cm.range(at: 1)))
            }
        }
        if token.hour == nil, let m = minuteRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            token.minute = Int(ns.substring(with: m.range(at: 1)))
        }

        guard token.isTimestampLine else { return nil }

        // 校验：时间戳行应基本由时间元素组成（移除时间字符后仅剩少量修饰词）
        let cleaned = text
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            .replacingOccurrences(
                of: "年|月|日|号|点|时|分|上午|下午|中午|晚上|凌晨|早上|今天|昨天|前天|明天|周|星期|[一二三四五六日天]|[0-9]|[:：]|[/.\\-]",
                with: "",
                options: .regularExpression
            )
        if !cleaned.isEmpty {
            let allowed = CharacterSet(charactersIn: "整左右前后约")
            let chars = cleaned.unicodeScalars
            guard chars.count <= 2, chars.allSatisfy({ allowed.contains($0) }) else { return nil }
        }
        return token
    }

    private static func resolve(token: TimeToken, now: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        if let y = token.year { comps.year = y }
        if let m = token.month { comps.month = m }
        if let d = token.day { comps.day = d }
        if let rel = token.relativeDay {
            let day = calendar.date(byAdding: .day, value: rel, to: now)!
            let dc = calendar.dateComponents([.year, .month, .day], from: day)
            comps.year = dc.year
            comps.month = dc.month
            comps.day = dc.day
        }
        if let wd = token.weekday {
            // 本周对应周几（周日=1）
            let today = calendar.component(.weekday, from: now)
            var delta = wd - today
            if delta < 0 { delta += 7 }
            let day = calendar.date(byAdding: .day, value: delta, to: now)!
            let dc = calendar.dateComponents([.year, .month, .day], from: day)
            comps.year = dc.year
            comps.month = dc.month
            comps.day = dc.day
        }
        var hour = token.hour
        if let h = hour, let p = token.period {
            switch p {
            case .afternoon, .evening, .night:
                if h < 12 { hour = h + 12 }
            case .morning:
                if h == 12 { hour = 0 }
            case .noon:
                hour = 12
            }
        }
        comps.hour = hour ?? 12
        comps.minute = token.minute ?? 0
        comps.second = 0
        return calendar.date(from: comps)
    }

    /// 把纯时刻行合并进最近的日期上下文
    private static func mergeTime(_ time: Date, into date: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        let tc = calendar.dateComponents([.hour, .minute], from: time)
        comps.hour = tc.hour
        comps.minute = tc.minute
        comps.second = 0
        return calendar.date(from: comps) ?? time
    }

    // MARK: - 内容提取

    private static func isMeaningfulContent(_ text: String) -> Bool {
        for pattern in systemLineRegexes {
            if text.range(of: pattern, options: .regularExpression) != nil { return false }
        }
        // 纯回复、纯表情等无信息量的行
        let lower = text.lowercased()
        let trivial: Set<String> = [
            "收到", "好的", "好", "嗯", "嗯嗯", "好的收到", "ok", "ok!", "okay", "谢谢", "感谢",
            "👍", "👌", "okay", "行", "可以", "好滴", "好嘞", "收到收到", "666", "哈哈", "哈哈哈",
        ]
        if trivial.contains(lower) { return false }
        // 至少包含一个中文字符或字母数字，才算有效内容
        return text.range(of: "[\\p{Han}a-zA-Z0-9]", options: .regularExpression) != nil
    }

    // MARK: - 账号名识别

    /// 从一行文本中提取对方账号名（消息前缀"张伟：…" / 系统消息"xx邀请你加入群聊"）
    private static func extractName(from text: String) -> String? {
        let ns = text as NSString
        // 消息前缀：张伟：内容
        if let m = namePrefixRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !nameBlacklist.contains(name) { return name }
        }
        // 系统消息：xx邀请你加入群聊 / xx撤回了一条消息
        if let m = systemNameRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !nameBlacklist.contains(name) { return name }
        }
        return nil
    }

    private static func makeSummary(from lines: [String], related: [String]) -> String? {
        // 主题优先取第一条核心需求句（包含需求关键词，最能概括主题）
        if let first = related.first {
            return String(Self.stripNamePrefix(first).prefix(20))
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            // 摘要要落在有需求含义的句子上
            let containsKw = requirementKeywords.contains { trimmed.contains($0) }
            if containsKw || trimmed.count >= 6 {
                return String(Self.stripNamePrefix(trimmed).prefix(24))
            }
        }
        return lines.first.map { String(Self.stripNamePrefix($0).prefix(24)) }
    }

    /// 去掉"张伟：…"式的名字前缀
    private static func stripNamePrefix(_ text: String) -> String {
        let ns = text as NSString
        if let m = namePrefixRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let full = m.range(at: 0) // 整个"名字："（含冒号）
            return ns.substring(from: full.location + full.length)
        }
        return text
    }

    private static func makeRelatedItems(from lines: [String]) -> [String] {
        var items: [String] = []
        var seen = Set<String>()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            guard requirementKeywords.contains(where: { trimmed.contains($0) }) else { continue }
            let normalized = trimmed.hasSuffix("。") || trimmed.hasSuffix("，") || trimmed.hasSuffix(",") || trimmed.hasSuffix(".")
                ? String(trimmed.dropLast()) : trimmed
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            items.append(String(normalized.prefix(40)))
            if items.count >= 8 { break }
        }
        return items
    }
}
