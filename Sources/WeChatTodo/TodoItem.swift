import Foundation

/// OCR + 规则解析的结果
struct ParsedResult {
    /// 需求产生时间（聊天中最后一条消息的时间）
    var createdAt: Date?
    /// 主题（需求摘要）
    var summary: String = ""
    /// 对方账号名
    var accountName: String?
    /// 完整聊天内容
    var detail: String = ""
    /// 相关需求列表
    var relatedItems: [String] = []
}

/// 一条待办便签
struct TodoItem: Codable {
    var id: String
    /// 主题
    var summary: String
    /// 对方账号名
    var accountName: String?
    var detail: String
    var relatedItems: [String]
    var createdAt: Date
    var completedAt: Date?
    /// 截图 PNG 文件名（存于 images 目录）
    var imagePath: String?
    /// OCR 原始文本（便于用户校对）
    var sourceText: String

    var isCompleted: Bool { completedAt != nil }

    init(
        id: String = UUID().uuidString,
        summary: String,
        accountName: String? = nil,
        detail: String,
        relatedItems: [String],
        createdAt: Date,
        completedAt: Date? = nil,
        imagePath: String? = nil,
        sourceText: String = ""
    ) {
        self.id = id
        self.summary = summary
        self.accountName = accountName
        self.detail = detail
        self.relatedItems = relatedItems
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.imagePath = imagePath
        self.sourceText = sourceText
    }
}
