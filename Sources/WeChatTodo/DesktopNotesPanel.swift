import AppKit
import CoreGraphics

/// 桌面常驻便签面板：贴桌面壁纸层 / 置顶悬浮 双模式，未完成待办自动贴上
final class DesktopNotesPanel: NSPanel {

    enum Mode: Int {
        case desktop = 0
        case floating = 1
    }

    private let store = TodoStore.shared

    private let toolBar = NSVisualEffectView()
    private let modeControl = NSSegmentedControl(labels: ["贴桌面", "置顶"], trackingMode: .selectOne, target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private let hideButton = NSButton()
    private let scrollView = NSScrollView()
    private let container = FlippedView()
    private let emptyLabel = NSTextField(labelWithString: "暂无未完成待办")

    private var currentMode: Mode = .desktop {
        didSet {
            updateLevel()
            UserDefaults.standard.set(currentMode.rawValue, forKey: "desktopPanelMode")
        }
    }

    /// 节流用的重排任务（避免窗口动画期间同步重建子视图导致崩溃）
    private var relayoutWorkItem: DispatchWorkItem?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        title = "桌面便签"
        // 关键：防止 AppKit 在窗口关闭/动画时额外 release 窗口对象（ARC 下会导致过度释放崩溃）
        isReleasedWhenClosed = false
        // 禁用显示/关闭的 transform 动画（与主窗口截图切换动画交错会触发过度释放崩溃）
        animationBehavior = .none

        let savedMode = UserDefaults.standard.integer(forKey: "desktopPanelMode")
        currentMode = Mode(rawValue: savedMode) ?? .desktop
        updateLevel()

        buildUI()
        restoreFrame()
        // 数据变化时异步节流刷新，避免在事件/动画栈内重建视图
        store.subscribe { [weak self] in
            DispatchQueue.main.async { self?.scheduleReload() }
        }
        reload()

        NotificationCenter.default.addObserver(self, selector: #selector(frameChanged), name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(frameChanged), name: NSWindow.didResizeNotification, object: self)
    }

    @objc private func frameChanged() {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "desktopPanelFrame")
        // 节流：窗口移动/缩放动画期间高频触发，延后 0.2s 再重排
        scheduleReload()
    }

    /// 节流重排：合并窗口动画/数据变化期间的多次触发
    private func scheduleReload() {
        relayoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        relayoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - 界面

    private func buildUI() {
        // 背景容器（圆角卡片）
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.86).cgColor
        bg.layer?.cornerRadius = 14
        bg.layer?.borderWidth = 0.5
        bg.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        bg.frame = contentView!.bounds
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        // 顶部工具条
        toolBar.frame = NSRect(x: 0, y: 0, width: bg.bounds.width, height: 44)
        toolBar.autoresizingMask = [.width, .minYMargin]
        toolBar.material = .popover
        bg.addSubview(toolBar)

        let title = NSTextField(labelWithString: "待办便签")
        title.font = .systemFont(ofSize: 12.5, weight: .semibold)
        title.frame = NSRect(x: 14, y: 11, width: 70, height: 22)
        toolBar.addSubview(title)

        modeControl.selectedSegment = currentMode.rawValue
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.frame = NSRect(x: 88, y: 7, width: 110, height: 28)
        toolBar.addSubview(modeControl)

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.frame = NSRect(x: 210, y: 12, width: 90, height: 18)
        toolBar.addSubview(countLabel)

        hideButton.title = "隐藏"
        hideButton.bezelStyle = .rounded
        hideButton.font = .systemFont(ofSize: 11)
        hideButton.target = self
        hideButton.action = #selector(hidePanel)
        hideButton.frame = NSRect(x: bg.bounds.width - 74, y: 7, width: 60, height: 28)
        hideButton.autoresizingMask = [.minXMargin]
        toolBar.addSubview(hideButton)

        // 便签区
        scrollView.frame = NSRect(x: 0, y: 44, width: bg.bounds.width, height: bg.bounds.height - 44)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        bg.addSubview(scrollView)
        container.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: 100)
        scrollView.documentView = container

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 0, y: 240, width: scrollView.bounds.width, height: 20)
        emptyLabel.isHidden = true
        bg.addSubview(emptyLabel)
    }

    private func updateLevel() {
        // 贴桌面：壁纸层之上、桌面图标之下；置顶：悬浮在所有窗口之上
        // 禁用窗口 level 切换动画：transform 动画期间重建视图会导致野指针崩溃
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        if currentMode == .desktop {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            becomesKeyOnlyIfNeeded = true
        } else {
            level = .floating
            becomesKeyOnlyIfNeeded = false
        }
        NSAnimationContext.endGrouping()
    }

    private func restoreFrame() {
        if let saved = UserDefaults.standard.string(forKey: "desktopPanelFrame"), saved != "" {
            let rect = NSRectFromString(saved)
            if rect.width > 0 {
                setFrame(rect, display: true)
                return
            }
        }
        // 默认放屏幕右上角
        if let screen = NSScreen.main {
            let r = NSRect(x: screen.visibleFrame.maxX - frame.width - 16, y: screen.visibleFrame.maxY - frame.height - 16, width: frame.width, height: frame.height)
            setFrame(r, display: true)
        }
    }

    // MARK: - 刷新

    private func reload() {
        container.subviews.forEach { $0.removeFromSuperview() }
        let pending = store.items.filter { !$0.isCompleted }
        countLabel.stringValue = "未完成 \(pending.count)"
        emptyLabel.isHidden = !pending.isEmpty

        guard !pending.isEmpty else {
            container.frame.size = NSSize(width: max(scrollView.contentSize.width, 200), height: 100)
            return
        }

        let width = max(scrollView.contentSize.width - 20, 220)
        var y: CGFloat = 10
        for item in pending {
            let card = DesktopNoteCard(item: item, width: width)
            card.onToggle = { [weak self] id in self?.store.toggle(id) }
            card.onDelete = { [weak self] id in self?.store.delete(id) }
            card.frame = NSRect(x: 10, y: y, width: width, height: card.bestHeight)
            container.addSubview(card)
            y += card.bestHeight + 10
        }
        container.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: y + 10)
    }

    // MARK: - 动作

    @objc private func modeChanged() {
        currentMode = Mode(rawValue: modeControl.selectedSegment) ?? .desktop
    }

    @objc private func hidePanel() {
        orderOut(nil)
    }

    func showPanel() {
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - 桌面便签卡片

final class DesktopNoteCard: NSView {
    let item: TodoItem
    var onToggle: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var bestHeight: CGFloat = 60

    private let check = CircularCheckControl()
    private let deleteBtn = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private var relLabels: [NSTextField] = []
    private let width: CGFloat

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
        layer?.cornerRadius = 10
        layer?.backgroundColor = Self.cardBackground.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.1).cgColor
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    private func setup() {
        let bodyX: CGFloat = 14
        let bodyW = width - 60

        check.frame = NSRect(x: width - 30, y: 12, width: 20, height: 20)
        check.checked = false
        check.onToggle = { [weak self] _ in
            guard let self else { return }
            self.onToggle?(self.item.id)
        }
        addSubview(check)

        deleteBtn.title = "✕"
        deleteBtn.isBordered = false
        deleteBtn.font = .systemFont(ofSize: 10)
        deleteBtn.contentTintColor = .secondaryLabelColor
        deleteBtn.setButtonType(.momentaryChange)
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteTapped)
        deleteBtn.frame = NSRect(x: width - 58, y: 13, width: 20, height: 18)
        addSubview(deleteBtn)

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

    @objc private func deleteTapped() {
        onDelete?(item.id)
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
