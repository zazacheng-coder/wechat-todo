import Foundation

/// 待办数据存储（JSON 持久化到 Application Support）
final class TodoStore {
    static let shared = TodoStore()

    private(set) var items: [TodoItem] = []
    private var listeners: [() -> Void] = []

    /// 订阅数据变化（数据变更后触发）
    func subscribe(_ listener: @escaping () -> Void) {
        listeners.append(listener)
    }

    private let dirURL: URL
    private let fileURL: URL
    private let imageDir: URL

    private init(baseURL: URL) {
        dirURL = baseURL.appendingPathComponent("WeChatTodo", isDirectory: true)
        fileURL = dirURL.appendingPathComponent("todos.json")
        imageDir = dirURL.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        load()
        schedulePrune()
    }

    convenience init(baseURL: URL? = nil) {
        let base = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(baseURL: base)
    }

    /// 运行期间周期检查：完成超一周的事项自动清除
    private func schedulePrune() {
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.pruneCompleted()
        }
    }

    // MARK: - 读写

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        // 与 save() 的 .iso8601 编码保持一致，否则日期解码失败导致数据"丢失"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([TodoItem].self, from: data)
        else { return }
        // 按创建时间倒序，未完成在前
        items = decoded.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            return a.createdAt > b.createdAt
        }
        // 完成超过一周的事项自动清除
        pruneCompleted()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
        listeners.forEach { $0() }
    }

    // MARK: - 操作

    func add(_ item: TodoItem) {
        items.insert(item, at: 0)
        save()
    }

    func toggle(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].completedAt = items[idx].isCompleted ? nil : Date()
        items.sort { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            return a.createdAt > b.createdAt
        }
        save()
    }

    func delete(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]
        if let path = item.imagePath {
            try? FileManager.default.removeItem(at: imageDir.appendingPathComponent(path))
        }
        items.remove(at: idx)
        save()
    }

    func update(_ id: String, summary: String? = nil, detail: String? = nil, relatedItems: [String]? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if let summary { items[idx].summary = summary }
        if let detail { items[idx].detail = detail }
        if let relatedItems { items[idx].relatedItems = relatedItems }
        save()
    }

    // MARK: - 自动清理

    /// 完成超过一周的事项自动清除（含截图文件）
    func pruneCompleted() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        var changed = false
        items = items.filter { item in
            if let done = item.completedAt, done < cutoff {
                if let path = item.imagePath {
                    try? FileManager.default.removeItem(at: imageDir.appendingPathComponent(path))
                }
                changed = true
                return false
            }
            return true
        }
        if changed { save() }
    }

    // MARK: - 图片

    func saveImagePNG(_ data: Data) -> String? {
        let name = UUID().uuidString + ".png"
        let url = imageDir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func imageURL(for name: String) -> URL? {
        let url = imageDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
