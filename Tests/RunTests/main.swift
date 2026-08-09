import Foundation
import AppKit

// 命令行验证 RequirementParser 的规则逻辑（无需 XCTest）
var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

func line(_ text: String, y: Double = 0.5, x: Double = 0.5) -> OCRService.Line {
    OCRService.Line(text: text, y: y, x: x)
}

func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    f.timeZone = .current
    return f.date(from: s)!
}

// 1. 完整日期 + 时刻
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("2026年8月1日", y: 0.9),
        line("下午 3:20", y: 0.85),
        line("老板，这周需要整理下季度销售数据", y: 0.8),
        line("下午 4:05", y: 0.75),
        line("麻烦周五前给我一版", y: 0.7),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.createdAt == date("2026-08-01 16:05:00"), "完整日期时间戳 → 最后一条消息时间 \(r.createdAt?.description ?? "nil")")
    check(r.summary.contains("整理"), "摘要包含需求关键词: \(r.summary)")
    check(r.relatedItems.count >= 2, "相关需求 >= 2: \(r.relatedItems)")
    check(r.detail.contains("销售数据"), "详情包含聊天内容")
}

// 2. 相对日期（昨天）+ 纯时刻
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("昨天", y: 0.9),
        line("上午 10:30", y: 0.85),
        line("需要把验收材料补充完整", y: 0.8),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.createdAt == date("2026-08-03 10:30:00"), "昨天+时刻合并 → \(r.createdAt?.description ?? "nil")")
}

// 3. 无时间戳 → 回退到 now
do {
    let now = date("2026-08-04 09:00:00")
    let r = RequirementParser.shared.parse(lines: [line("请尽快处理下这个风险", y: 0.8)], now: now)
    check(r.createdAt == now, "无时间戳回退 now")
}

// 4. 过滤系统行与纯回复
do {
    let lines = [
        line("以上是本次聊天记录", y: 0.9),
        line("收到", y: 0.8),
        line("好的，我去确认下", y: 0.7),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: date("2026-08-04 09:00:00"))
    check(!r.detail.contains("聊天记录"), "过滤系统行")
    check(!r.detail.contains("收到"), "过滤纯回复")
    check(r.detail.contains("确认"), "保留有效内容")
}

// 5. 相关需求提取
do {
    let lines = [
        line("下午 2:00", y: 0.9),
        line("帮我排一下下周的评审会议", y: 0.85),
        line("顺便统计一下各项目进度", y: 0.8),
        line("收到", y: 0.75),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: date("2026-08-04 09:00:00"))
    check(r.relatedItems.contains(where: { $0.contains("评审") }), "提取评审需求: \(r.relatedItems)")
    check(r.relatedItems.contains(where: { $0.contains("统计") }), "提取统计需求: \(r.relatedItems)")
    check(!r.relatedItems.contains(where: { $0.contains("收到") }), "回复不进入需求")
}

// 6. 消息内容含"下午3点"不应误判为时间戳
do {
    let now = date("2026-08-04 09:00:00")
    let lines = [
        line("8月4日", y: 0.9),
        line("上午 9:00", y: 0.85),
        line("下午3点要开会，记得准备好材料", y: 0.8),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.createdAt == date("2026-08-04 09:00:00"), "消息文本不被误判时间戳: \(r.createdAt?.description ?? "nil")")
    check(r.detail.contains("开会"), "消息内容保留")
}

// 7. 未完成卡片样式所需的 formatTime 展示
do {
    let f = DateFormatter()
    f.dateFormat = "M月d日 HH:mm"
    check(f.string(from: date("2026-08-04 10:00:00")) == "8月4日 10:00", "时间格式化")
}

// 8. 钉钉/飞书样式：2026-08-04 10:20
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("2026-08-04 10:20", y: 0.9),
        line("需要把上线计划发我一份", y: 0.85),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.createdAt == date("2026-08-04 10:20:00"), "横线日期+时刻: \(r.createdAt?.description ?? "nil")")
    check(r.relatedItems.contains(where: { $0.contains("上线计划") }), "需求提取: \(r.relatedItems)")
}

// 9. 短日期 8-04 + 时刻
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("8-04", y: 0.9),
        line("14:30", y: 0.85),
        line("确认一下下周排期", y: 0.8),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.createdAt == date("2026-08-04 14:30:00"), "短日期+时刻合并: \(r.createdAt?.description ?? "nil")")
}

// 10. 周几
do {
    let now = date("2026-08-04 15:00:00") // 2026-08-04 是周三
    let lines = [
        line("周四", y: 0.9),
        line("14:00", y: 0.85),
        line("准备评审材料", y: 0.8),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.createdAt == date("2026-08-05 14:00:00"), "周四=本周四: \(r.createdAt?.description ?? "nil")")
}

// 11. 消息含"周四"不应误判为时间戳
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("8月4日", y: 0.9),
        line("下午 2:00", y: 0.85),
        line("周四前给我一版方案", y: 0.8),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.createdAt == date("2026-08-04 14:00:00"), "消息含周四不误判: \(r.createdAt?.description ?? "nil")")
    check(r.detail.contains("方案"), "消息内容保留")
}

// 12. 对方账号名识别（消息前缀"张伟："）
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("下午 3:20", y: 0.9),
        line("张伟：这周需要整理下季度销售数据", y: 0.85),
        line("下午 4:05", y: 0.8),
        line("张伟：麻烦周五前给我一版", y: 0.75),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.accountName == "张伟", "账号名=张伟: \(r.accountName ?? "nil")")
    check(r.summary.contains("整理"), "主题用核心需求句: \(r.summary)")
}

// 13. 群聊多账号名 → 取出现次数最多者
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("下午 2:00", y: 0.9),
        line("李娜：这个需求排期有问题", y: 0.85),
        line("下午 2:10", y: 0.8),
        line("王强：我这边没问题", y: 0.75),
        line("下午 2:20", y: 0.7),
        line("李娜：麻烦明天前确认", y: 0.65),
        line("下午 2:30", y: 0.6),
        line("王强：收到，我明天给你", y: 0.55),
        line("下午 2:40", y: 0.5),
        line("李娜：好的，谢谢", y: 0.45),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.accountName == "李娜", "群聊取出现最多者=李娜: \(r.accountName ?? "nil")")
}

// 14. 系统消息提取账号名 + 主题优先需求句
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("下午 3:00", y: 0.9),
        line("陈静邀请你加入群聊", y: 0.85),
        line("下午 3:05", y: 0.8),
        line("麻烦统计一下本周各渠道数据", y: 0.75),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.accountName == "陈静", "系统消息提取账号名=陈静: \(r.accountName ?? "nil")")
    check(r.summary.contains("统计"), "主题=统计需求: \(r.summary)")
}

// 15. 无账号名（纯聊天内容无前缀）→ 不误判
do {
    let now = date("2026-08-04 15:00:00")
    let lines = [
        line("下午 3:00", y: 0.9),
        line("需要把验收材料补充完整", y: 0.8),
    ]
    let r = RequirementParser.shared.parse(lines: lines, now: now)
    check(r.accountName == nil, "无前缀不误判账号名: \(r.accountName ?? "nil")")
}

// 16. 本地持久化：保存后重新加载，未完成事项不丢失
do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wct-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let storeA = TodoStore(baseURL: tmp)
    storeA.add(TodoItem(summary: "整理周报", detail: "本周数据", relatedItems: ["整理周报"], createdAt: date("2026-08-04 10:00:00")))
    storeA.toggle(storeA.items[0].id) // 标记完成
    storeA.add(TodoItem(summary: "未完成事项", detail: "保留", relatedItems: [], createdAt: date("2026-08-05 09:00:00")))

    // 模拟退出重开：新实例重新 load
    let storeB = TodoStore(baseURL: tmp)
    check(storeB.items.contains { $0.summary == "未完成事项" }, "重启后未完成事项保留")
    check(storeB.items.contains { $0.summary == "整理周报" && $0.isCompleted }, "重启后已完成状态保留")
    try? FileManager.default.removeItem(at: tmp)
}

// 17. 完成超一周自动清除，未超一周保留
do {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wct-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let store = TodoStore(baseURL: tmp)
    let now = Date()
    store.add(TodoItem(summary: "八天前完成", detail: "", relatedItems: [], createdAt: now.addingTimeInterval(-10 * 86400), completedAt: now.addingTimeInterval(-8 * 86400))) // 完成 8 天
    store.add(TodoItem(summary: "两天前完成", detail: "", relatedItems: [], createdAt: now.addingTimeInterval(-4 * 86400), completedAt: now.addingTimeInterval(-2 * 86400))) // 完成 2 天
    store.add(TodoItem(summary: "未完成", detail: "", relatedItems: [], createdAt: now.addingTimeInterval(-1 * 86400)))

    store.pruneCompleted()
    check(!store.items.contains { $0.summary == "八天前完成" }, "完成超一周自动清除")
    check(store.items.contains { $0.summary == "两天前完成" }, "完成未超一周保留")
    check(store.items.contains { $0.summary == "未完成" }, "未完成事项保留")
    try? FileManager.default.removeItem(at: tmp)
}

print(failures == 0 ? "\n全部通过 ✅" : "\n失败 \(failures) 项 ❌")
exit(failures == 0 ? 0 : 1)
