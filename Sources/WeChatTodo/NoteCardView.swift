import AppKit

/// 圆形勾选控件（便签的"完成"按钮）
final class CircularCheckControl: NSView {
    var checked: Bool = false {
        didSet { needsDisplay = true }
    }
    var onToggle: ((Bool) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 2.5, dy: 2.5)
        let path = NSBezierPath(ovalIn: inset)
        if checked {
            NSColor.systemGreen.setFill()
            path.fill()
        } else {
            let fill = NSColor(calibratedWhite: 0.5, alpha: 0.12)
            fill.setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 1.4
            path.stroke()
        }
        if checked {
            let tick = NSBezierPath()
            // 标准对勾（y 向上坐标系）：左上 → 中下 → 右上
            tick.move(to: NSPoint(x: inset.minX + 0.26 * inset.width, y: inset.midY + 0.2 * inset.height))
            tick.line(to: NSPoint(x: inset.minX + 0.44 * inset.width, y: inset.midY - 0.24 * inset.height))
            tick.line(to: NSPoint(x: inset.maxX - 0.2 * inset.width, y: inset.midY + 0.2 * inset.height))
            tick.lineWidth = 2.0
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        checked.toggle()
        onToggle?(checked)
    }
}

/// 删除按钮（右上角 ×，悬停变红）
final class DeleteButtonView: NSView {
    var onDelete: (() -> Void)?
    private var hovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("删除便签")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.systemRed.withAlphaComponent(0.15).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        }
        let inset = bounds.insetBy(dx: 6, dy: 6)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: inset.minX, y: inset.minY))
        line.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        line.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        line.line(to: NSPoint(x: inset.minX, y: inset.maxY))
        line.lineWidth = 1.6
        line.lineCapStyle = .round
        (hovered ? NSColor.systemRed : NSColor.secondaryLabelColor).setStroke()
        line.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        onDelete?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}

/// 单张便签卡片（黄纸样式）
final class NoteCardView: NSView {
    let item: TodoItem
    var onToggle: ((String) -> Void)?
    var onOpenImage: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var bestHeight: CGFloat = 140

    private let cardWidth: CGFloat
    private let checkView = CircularCheckControl()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var relatedLabels: [NSTextField] = []
    private let thumbView = NSImageView()

    static var noteBackground: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor(calibratedRed: 0.33, green: 0.31, blue: 0.18, alpha: 1.0)
            }
            return NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.78, alpha: 1.0)
        }
    }

    init(item: TodoItem, width: CGFloat) {
        self.item = item
        self.cardWidth = width
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = Self.noteBackground.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.masksToBounds = false
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    private func setup() {
        // 勾选按钮（右上角）
        checkView.frame = NSRect(x: cardWidth - 62, y: 12, width: 22, height: 22)
        checkView.checked = item.isCompleted
        checkView.onToggle = { [weak self] _ in
            guard let self else { return }
            self.onToggle?(self.item.id)
        }
        addSubview(checkView)

        // 删除按钮（勾选按钮左侧的 ×）
        let deleteBtn = DeleteButtonView(frame: NSRect(x: cardWidth - 33, y: 13, width: 20, height: 20))
        deleteBtn.onDelete = { [weak self] in
            guard let self else { return }
            self.onDelete?(self.item.id)
        }
        addSubview(deleteBtn)

        // 标题
        titleLabel.stringValue = item.summary.isEmpty ? "（无标题）" : item.summary
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        addSubview(titleLabel)

        // 时间（含对方账号名）："张伟 · 8月4日 10:15"
        if let name = item.accountName, !name.isEmpty {
            timeLabel.stringValue = "\(name) · \(Self.formatTime(item.createdAt))"
        } else {
            timeLabel.stringValue = Self.formatTime(item.createdAt)
        }
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        addSubview(timeLabel)

        // 相关需求
        for rel in item.relatedItems {
            let label = NSTextField(labelWithString: "·  " + rel)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 2
            relatedLabels.append(label)
            addSubview(label)
        }

        // 详情
        detailLabel.stringValue = item.detail
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 3
        addSubview(detailLabel)

        // 缩略图
        if let path = item.imagePath, let url = TodoStore.shared.imageURL(for: path), let img = NSImage(contentsOf: url) {
            thumbView.image = img
            thumbView.imageScaling = .scaleProportionallyUpOrDown
            thumbView.wantsLayer = true
            thumbView.layer?.cornerRadius = 6
            thumbView.layer?.masksToBounds = true
            thumbView.layer?.borderWidth = 0.5
            thumbView.layer?.borderColor = NSColor.black.withAlphaComponent(0.1).cgColor
            let click = NSClickGestureRecognizer(target: self, action: #selector(openImage))
            thumbView.addGestureRecognizer(click)
            addSubview(thumbView)
        }

        // 右键删除
        let menu = NSMenu()
        let deleteItem = NSMenuItem(title: "删除便签", action: #selector(deleteNote), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        self.menu = menu

        layoutCard()
    }

    /// 计算内容总高度并一次性布局（容器为 flipped 坐标系，y 从顶部向下）
    private func layoutCard() {
        let bodyX: CGFloat = 12
        let bodyWidth = cardWidth - 24
        var y: CGFloat = 12

        // 标题行（给右上角两个按钮留空间）
        titleLabel.frame = NSRect(x: bodyX, y: y, width: bodyWidth - 70, height: 20)
        y += 20
        // 时间行
        timeLabel.frame = NSRect(x: bodyX, y: y, width: bodyWidth, height: 15)
        y += 21

        // 相关需求
        for (i, label) in relatedLabels.enumerated() {
            let text = item.relatedItems[i]
            let h = Self.clampHeight(text, font: label.font!, width: bodyWidth, maxLines: 2, base: 16)
            label.frame = NSRect(x: bodyX, y: y, width: bodyWidth, height: h)
            y += h + 3
        }
        if !relatedLabels.isEmpty { y += 4 }

        // 详情
        if !item.detail.isEmpty {
            let h = Self.clampHeight(item.detail, font: detailLabel.font!, width: bodyWidth, maxLines: 3, base: 14)
            detailLabel.frame = NSRect(x: bodyX, y: y, width: bodyWidth, height: h)
            y += h + 6
        }

        // 缩略图
        if thumbView.image != nil {
            let thumbH: CGFloat = 76
            thumbView.frame = NSRect(x: bodyX, y: y, width: bodyWidth, height: thumbH)
            y += thumbH + 6
        }

        y += 6
        bestHeight = max(y, 78)
    }

    /// 计算换行高度并截断文本
    private static func clampHeight(_ text: String, font: NSFont, width: CGFloat, maxLines: Int, base: CGFloat) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attr = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: para])
        let size = attr.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let maxH = ceil(font.boundingRectForFont.height) * CGFloat(maxLines)
        return min(ceil(size.height) + 2, maxH)
    }

    private static func formatTime(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "今天 HH:mm"
        } else if cal.isDateInYesterday(date) {
            f.dateFormat = "昨天 HH:mm"
        } else {
            let year = cal.component(.year, from: date)
            f.dateFormat = year == cal.component(.year, from: Date()) ? "M月d日 HH:mm" : "yyyy年M月d日 HH:mm"
        }
        return f.string(from: date)
    }

    /// 完成态样式刷新
    func refreshCompletedStyle() {
        let completed = item.isCompleted
        checkView.checked = completed
        titleLabel.attributedStringValue = {
            let attr = NSMutableAttributedString(
                string: item.summary.isEmpty ? "（无标题）" : item.summary,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                    .strikethroughStyle: completed ? NSUnderlineStyle.single.rawValue : 0,
                ]
            )
            return attr
        }()
        alphaValue = completed ? 0.55 : 1.0
    }

    @objc private func openImage() {
        if let path = item.imagePath {
            onOpenImage?(path)
        }
    }

    @objc private func deleteNote() {
        onDelete?(item.id)
    }
}
