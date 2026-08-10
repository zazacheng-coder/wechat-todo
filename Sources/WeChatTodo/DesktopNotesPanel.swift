import AppKit
import CoreGraphics

/// 桌面小组件模式：贴桌面壁纸层 / 置顶悬浮
enum DesktopWidgetMode: Int {
    case desktop = 0
    case floating = 1
}

/// 桌面小组件窗口：一个未完成待办 = 一张独立小卡片贴在桌面，
/// 可拖动（位置自动记忆）、单击跳转到便签应用主窗口操作。
/// 注：desktopWindow 层级无法成为 key window，按钮 action 无法触发，
/// 故去掉完成/删除按钮，改为点击卡片整体跳转。
final class DesktopWidgetPanel: NSPanel {

    static let widgetWidth: CGFloat = 260

    let itemID: String
    var onActivate: (() -> Void)?

    private var card: DesktopNoteCard!

    init(item: TodoItem, mode: DesktopWidgetMode) {
        self.itemID = item.id
        let card = DesktopNoteCard(item: item, width: Self.widgetWidth)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.widgetWidth, height: card.bestHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        // 手动实现拖动（mouseDown/mouseDragged），以便区分单击跳转与拖动
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        title = "待办小组件"
        // 关键：防止 AppKit 在窗口关闭/动画时额外 release 窗口对象（ARC 下会导致过度释放崩溃）
        isReleasedWhenClosed = false
        // 禁用显示/关闭的 transform 动画（与主窗口截图切换动画交错会触发过度释放崩溃）
        animationBehavior = .none

        self.card = card
        card.onActivate = { [weak self] in self?.onActivate?() }
        contentView = card

        apply(mode: mode)
        restoreFrame()

        // 位置持久化：拖动后记忆每个小组件的位置
        NotificationCenter.default.addObserver(self, selector: #selector(frameChanged), name: NSWindow.didMoveNotification, object: self)
    }

    @objc private func frameChanged() {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "desktopWidgetFrame-\(itemID)")
    }

    /// 应用贴桌面/置顶层级（禁用动画，避免 transform 动画期间重建视图导致崩溃）
    func apply(mode: DesktopWidgetMode) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        if mode == .desktop {
            // 贴桌面壁纸层（桌面图标之下）。+偏移会导致窗口不再被当作桌面窗口渲染而消失，
            // 故保持原 desktopWindow level；点击通过 canBecomeKey + becomesKeyOnlyIfNeeded=false 解决
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        } else {
            level = .floating
        }
        // 关键：两种模式都设 false，确保点击完成/删除按钮时立即成为 key 并触发 action，
        // 否则 becomesKeyOnlyIfNeeded=true 会导致第一次点击只激活窗口、不触发按钮
        becomesKeyOnlyIfNeeded = false
        NSAnimationContext.endGrouping()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func restoreFrame() {
        if let saved = UserDefaults.standard.string(forKey: "desktopWidgetFrame-\(itemID)"), saved != "" {
            let rect = NSRectFromString(saved)
            if rect.width > 0, rect.height > 0 {
                setFrame(rect, display: false)
                return
            }
        }
        // 首次出现：以屏幕右侧垂直中点为基准，按创建顺序依次向下排
        if let screen = NSScreen.main {
            let midY = screen.visibleFrame.midY
            let y = midY + frame.height / 2 - CGFloat(indexInColumn) * (frame.height + 12)
            setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - frame.width - 16, y: y))
        }
    }

    private var indexInColumn: Int = 0

    /// 指定默认排列序号（用于新小组件避免重叠）
    func setDefaultColumnIndex(_ index: Int) {
        indexInColumn = index
        if UserDefaults.standard.string(forKey: "desktopWidgetFrame-\(itemID)") == nil {
            if let screen = NSScreen.main {
                let midY = screen.visibleFrame.midY
                let y = midY + frame.height / 2 - CGFloat(index) * (frame.height + 12)
                setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - frame.width - 16, y: y))
            }
        }
    }

    func showWidget() {
        guard !isVisible else { return }
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - 桌面小组件卡片

final class DesktopNoteCard: NSView {
    let item: TodoItem
    var onActivate: (() -> Void)?
    var bestHeight: CGFloat = 60

    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private var relLabels: [NSTextField] = []
    private let width: CGFloat

    // 拖动与单击区分
    private var mouseDownPoint: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var didDrag = false

    static var cardBackground: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor(calibratedRed: 0.38, green: 0.35, blue: 0.20, alpha: 0.96)
            }
            return NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.72, alpha: 0.96)
        }
    }

    init(item: TodoItem, width: CGFloat) {
        self.item = item
        self.width = width
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = Self.cardBackground.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.1).cgColor
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    private func setup() {
        let bodyX: CGFloat = 14
        let bodyW = width - 28

        titleLabel.stringValue = item.summary.isEmpty ? "（无标题）" : item.summary
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        addSubview(titleLabel)

        if let name = item.accountName, !name.isEmpty {
            timeLabel.stringValue = "\(name) · \(Self.formatTime(item.createdAt))"
        } else {
            timeLabel.stringValue = Self.formatTime(item.createdAt)
        }
        timeLabel.font = .systemFont(ofSize: 10.5)
        timeLabel.textColor = .secondaryLabelColor
        addSubview(timeLabel)

        for rel in item.relatedItems.prefix(2) {
            let l = NSTextField(labelWithString: "·  " + rel)
            l.font = .systemFont(ofSize: 11)
            l.textColor = .labelColor.withAlphaComponent(0.85)
            l.lineBreakMode = .byTruncatingTail
            l.maximumNumberOfLines = 1
            relLabels.append(l)
            addSubview(l)
        }

        layoutContent(bodyX: bodyX, bodyW: bodyW)
    }

    private func layoutContent(bodyX: CGFloat, bodyW: CGFloat) {
        var y: CGFloat = 12
        titleLabel.frame = NSRect(x: bodyX, y: y, width: bodyW, height: 18)
        y += 20
        timeLabel.frame = NSRect(x: bodyX, y: y, width: bodyW, height: 14)
        y += 18
        for label in relLabels {
            label.frame = NSRect(x: bodyX, y: y, width: bodyW, height: 16)
            y += 18
        }
        y += 4
        bestHeight = y
    }

    // MARK: - 拖动 + 单击跳转（手动实现，区分拖动与点击）

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin ?? .zero
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownPoint.x
        let dy = current.y - mouseDownPoint.y
        if !didDrag && (abs(dx) > 4 || abs(dy) > 4) {
            didDrag = true
        }
        if didDrag, let win = window {
            win.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + dx, y: initialWindowOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        // 未拖动 = 单击：跳转到便签应用主窗口
        if !didDrag {
            onActivate?()
        }
    }

    private static func formatTime(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "今天 HH:mm"
        } else if cal.isDateInYesterday(date) {
            f.dateFormat = "昨天 HH:mm"
        } else {
            f.dateFormat = cal.component(.year, from: date) == cal.component(.year, from: Date()) ? "M月d日 HH:mm" : "yyyy年M月d日 HH:mm"
        }
        return f.string(from: date)
    }
}
