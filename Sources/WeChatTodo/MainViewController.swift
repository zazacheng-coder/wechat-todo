import AppKit

/// 便签墙主界面
final class MainViewController: NSViewController {

    enum Filter: Int {
        case all = 0, pending, completed
    }

    private let store = TodoStore.shared

    private let toolbar = NSVisualEffectView()
    private let appTitle = NSTextField(labelWithString: "便签待办")
    private let screenshotButton = NSButton()
    private let pasteButton = NSButton()
    private let newButton = NSButton()
    private let desktopCheckbox = NSButton(checkboxWithTitle: "桌面小组件", target: nil, action: nil)
    private let filterControl = NSSegmentedControl(labels: ["全部", "待办", "已完成"], trackingMode: .selectOne, target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    /// 桌面小组件：每个未完成待办一张独立卡片
    private var desktopWidgets: [String: DesktopWidgetPanel] = [:]
    private var desktopWidgetMode: DesktopWidgetMode = {
        DesktopWidgetMode(rawValue: UserDefaults.standard.integer(forKey: "desktopPanelMode")) ?? .desktop
    }()
    private var desktopWidgetsVisible = true

    private let scrollView = NSScrollView()
    private let container = FlippedView()
    private let emptyView = NSView()
    private let dragDropView = DragDropView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var processing = false

    private var filter: Filter = .all
    /// 内置截图启动时预读的聊天窗口标题（截图瞬间前台是聊天软件）
    private var pendingChatTitle: String?
    /// 节流用的重排任务（避免布局/事件期间同步重建子视图导致崩溃）
    private var layoutWorkItem: DispatchWorkItem?
    /// 图片查看窗口（长期持有复用：点红叉仅隐藏不销毁，避免窗口关闭动画崩溃）
    private var imageDetailWindow: NSWindow?
    /// 图片查看文档视图（可滚动，图片在可见区域内居中）
    private var imageDetailDoc: ImageCenterView?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1080, height: 720))
        view.wantsLayer = true
        buildToolbar()
        buildBody()
        buildStatusBar()
        reload()
        // 数据变化时异步刷新，避免在事件/动画栈内重建视图
        store.subscribe { [weak self] in
            DispatchQueue.main.async {
                self?.reload()
                self?.syncDesktopWidgets()
            }
        }
        // 默认开启桌面常驻小组件
        desktopCheckbox.state = .on
        syncDesktopWidgets()
        // 监听剪贴板变化可选的增强，此处不做
    }

    // MARK: - 界面搭建

    private func buildToolbar() {
        toolbar.frame = NSRect(x: 0, y: view.bounds.height - 56, width: view.bounds.width, height: 56)
        toolbar.autoresizingMask = [.width, .minYMargin]
        toolbar.material = .headerView
        view.addSubview(toolbar)

        appTitle.font = .systemFont(ofSize: 16, weight: .bold)
        appTitle.textColor = .labelColor
        appTitle.frame = NSRect(x: 16, y: 14, width: 100, height: 28)
        toolbar.addSubview(appTitle)

        screenshotButton.title = "📷 截图"
        screenshotButton.bezelStyle = .rounded
        screenshotButton.font = .systemFont(ofSize: 12.5)
        screenshotButton.target = self
        screenshotButton.action = #selector(captureScreenshot)
        screenshotButton.sizeToFit()
        screenshotButton.frame = NSRect(x: 118, y: 13, width: screenshotButton.frame.width + 22, height: 30)
        screenshotButton.toolTip = "内置截图：抓取屏幕后框选聊天记录，自动生成便签（需屏幕录制权限）"
        toolbar.addSubview(screenshotButton)

        pasteButton.title = "⌘V 粘贴截图"
        pasteButton.bezelStyle = .rounded
        pasteButton.font = .systemFont(ofSize: 12.5)
        pasteButton.target = self
        pasteButton.action = #selector(pasteFromClipboard(_:))
        pasteButton.sizeToFit()
        pasteButton.frame = NSRect(x: screenshotButton.frame.maxX + 10, y: 13, width: pasteButton.frame.width + 24, height: 30)
        toolbar.addSubview(pasteButton)

        newButton.title = "新建便签"
        newButton.bezelStyle = .rounded
        newButton.font = .systemFont(ofSize: 12.5)
        newButton.target = self
        newButton.action = #selector(createManualNote)
        newButton.sizeToFit()
        newButton.frame = NSRect(x: pasteButton.frame.maxX + 10, y: 13, width: newButton.frame.width + 24, height: 30)
        toolbar.addSubview(newButton)

        desktopCheckbox.target = self
        desktopCheckbox.action = #selector(toggleDesktopPanel)
        desktopCheckbox.font = .systemFont(ofSize: 12.5)
        desktopCheckbox.sizeToFit()
        desktopCheckbox.frame = NSRect(x: newButton.frame.maxX + 18, y: 11, width: desktopCheckbox.frame.width + 8, height: 30)
        desktopCheckbox.toolTip = "未完成待办以独立小组件卡片贴在桌面（可拖动，点击图钉切换贴桌面/置顶）"
        toolbar.addSubview(desktopCheckbox)

        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        filterControl.frame = NSRect(x: view.bounds.width - 260, y: 13, width: 180, height: 30)
        filterControl.autoresizingMask = [.minXMargin]
        toolbar.addSubview(filterControl)

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.frame = NSRect(x: view.bounds.width - 296, y: 17, width: 30, height: 22)
        countLabel.autoresizingMask = [.minXMargin]
        toolbar.addSubview(countLabel)
    }

    private func buildBody() {
        dragDropView.frame = NSRect(x: 0, y: 24, width: view.bounds.width, height: view.bounds.height - 56 - 24)
        dragDropView.autoresizingMask = [.width, .height]
        dragDropView.onImageDrop = { [weak self] image in
            self?.process(image: image)
        }
        view.addSubview(dragDropView)

        scrollView.frame = dragDropView.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        dragDropView.addSubview(scrollView)

        container.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: 400)
        scrollView.documentView = container

        // 空状态引导
        emptyView.frame = scrollView.bounds
        emptyView.autoresizingMask = [.width, .height]
        let icon = NSTextField(labelWithString: "📋")
        icon.font = .systemFont(ofSize: 44)
        icon.alignment = .center
        icon.frame = NSRect(x: 0, y: 200, width: scrollView.bounds.width, height: 60)
        icon.autoresizingMask = [.width]
        emptyView.addSubview(icon)
        let title = NSTextField(labelWithString: "粘贴聊天截图，自动生成待办便签")
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.alignment = .center
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: 0, y: 160, width: scrollView.bounds.width, height: 24)
        title.autoresizingMask = [.width]
        emptyView.addSubview(title)
        let hint = NSTextField(labelWithString: "复制微信 / QQ / 钉钉 / 飞书等聊天截图，在此处按 ⌘V（或点击左上角按钮）")
        hint.font = .systemFont(ofSize: 12)
        hint.alignment = .center
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 0, y: 132, width: scrollView.bounds.width, height: 20)
        hint.autoresizingMask = [.width]
        emptyView.addSubview(hint)
        let shotHint = NSTextField(labelWithString: "macOS 截图：⌘⇧3 全屏 · ⌘⇧4 框选 · ⌘⇧5 截图工具　|　⌃⌘⇧4 框选后直接存入剪贴板")
        shotHint.font = .systemFont(ofSize: 12)
        shotHint.alignment = .center
        shotHint.textColor = .tertiaryLabelColor
        shotHint.frame = NSRect(x: 0, y: 104, width: scrollView.bounds.width, height: 20)
        shotHint.autoresizingMask = [.width]
        emptyView.addSubview(shotHint)
        scrollView.addSubview(emptyView)
    }

    private func buildStatusBar() {
        statusLabel.font = .systemFont(ofSize: 11.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 16, y: 5, width: view.bounds.width - 32, height: 16)
        statusLabel.autoresizingMask = [.width]
        statusLabel.stringValue = "截图 ⌘⇧4 框选 · ⌃⌘⇧4 直接入剪贴板 · 粘贴 ⌘V · 拖入图片 · 点击 ○ 完成 · 点击 × 删除"
        view.addSubview(statusLabel)
    }

    // MARK: - 数据加载与布局

    private func visibleItems() -> [TodoItem] {
        switch filter {
        case .all: return store.items
        case .pending: return store.items.filter { !$0.isCompleted }
        case .completed: return store.items.filter { $0.isCompleted }
        }
    }

    private func reload() {
        container.subviews.forEach { $0.removeFromSuperview() }
        let items = visibleItems()

        // 计数
        let pendingCount = store.items.filter { !$0.isCompleted }.count
        countLabel.stringValue = "\(pendingCount)"
        countLabel.toolTip = "待办 \(pendingCount) · 已完成 \(store.items.count - pendingCount)"

        emptyView.isHidden = !store.items.isEmpty

        guard !items.isEmpty else {
            container.frame.size = NSSize(width: max(scrollView.contentSize.width, 200), height: 400)
            return
        }

        layoutCards(items: items)
        emptyView.isHidden = true
    }

    private func layoutCards(items: [TodoItem]) {
        let usableWidth = max(scrollView.contentSize.width, 200)
        let gap: CGFloat = 16
        let cardWidth: CGFloat = 264
        let cols = max(1, Int((usableWidth + gap) / (cardWidth + gap)))
        let totalGap = CGFloat(cols - 1) * gap
        let actualW = (usableWidth - totalGap) / CGFloat(cols)

        var colHeights = [CGFloat](repeating: 0, count: cols)
        var cardViews: [NoteCardView] = []

        for item in items {
            let card = NoteCardView(item: item, width: actualW)
            card.onToggle = { [weak self] id in
                self?.store.toggle(id)
            }
            card.onDelete = { [weak self] id in
                self?.confirmDelete(id)
            }
            card.onOpenImage = { [weak self] path in
                self?.openImageDetail(path)
            }
            card.refreshCompletedStyle()

            let col = colHeights.indices.min(by: { colHeights[$0] < colHeights[$1] })!
            let x = CGFloat(col) * (actualW + gap)
            let y = colHeights[col]
            card.frame = NSRect(x: x, y: y, width: actualW, height: card.bestHeight)
            container.addSubview(card)
            colHeights[col] += card.bestHeight + gap
            cardViews.append(card)
        }

        let height = max((colHeights.max() ?? 0), 400)
        container.frame = NSRect(x: 0, y: 0, width: usableWidth, height: height)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // 节流：resize 期间频繁触发，延后到布局稳定后再重排
        layoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        layoutWorkItem = item
        DispatchQueue.main.async(execute: item)
    }

    // MARK: - 内置截图

    @objc func captureScreenshot() {
        guard !processing else { return }
        guard ScreenshotService.hasPermission() else {
            showMessage("需要「屏幕录制」权限", info: "请在 系统设置 → 隐私与安全性 → 屏幕录制 中勾选「便签待办」，然后重新截图。\n\n（首次使用截图功能时系统也会弹出授权提示）")
            return
        }
        processing = true
        screenshotButton.isEnabled = false
        statusLabel.stringValue = "准备截图，请切换到要截取的窗口…"
        // 截图前预读聊天窗口标题（此刻前台是聊天软件，最准确）
        pendingChatTitle = ChatWindowReader.currentChatTitle()

        // 隐藏主窗口，避免截到自身；稍后抓屏再恢复
        let wasVisible = view.window?.isVisible ?? false
        view.window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            // 先截屏（此刻主窗口已隐藏，屏幕干净），再恢复主窗口，
            // 避免主窗口显示动画与 CGDisplayCreateImage 截屏交错触发过度释放崩溃
            guard let cg = ScreenshotService.captureMainDisplay(), let screen = NSScreen.main else {
                if wasVisible { self.view.window?.makeKeyAndOrderFront(nil) }
                self.processing = false
                self.screenshotButton.isEnabled = true
                self.statusLabel.stringValue = "截图失败，请重试"
                return
            }
            if wasVisible { self.view.window?.makeKeyAndOrderFront(nil) }
            let img = NSImage(cgImage: cg, size: screen.frame.size)
            let overlay = CaptureOverlayWindow(
                screen: screen,
                image: img,
                onCapture: { [weak self] cropped in
                    self?.process(image: cropped)
                },
                onCancel: { [weak self] in
                    self?.processing = false
                    self?.screenshotButton.isEnabled = true
                    self?.statusLabel.stringValue = "已取消截图"
                }
            )
            overlay.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - 粘贴 / OCR 流程

    @objc func pasteFromClipboard(_ sender: Any?) {
        guard !processing else { return }
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png), let img = NSImage(data: data) {
            process(image: img)
            return
        }
        if let data = pb.data(forType: .tiff), let img = NSImage(data: data) {
            process(image: img)
            return
        }
        // 复制图片文件
        if let data = pb.data(forType: .fileURL),
           let url = URL(string: String(data: data, encoding: .utf8) ?? ""),
           let img = NSImage(contentsOf: url) {
            process(image: img)
            return
        }
        showMessage("剪贴板中没有找到图片", info: "请先复制一张聊天截图（微信/QQ/钉钉/飞书等），再按 ⌘V")
    }

    private func process(image: NSImage) {
        processing = true
        pasteButton.isEnabled = false
        screenshotButton.isEnabled = false
        statusLabel.stringValue = "正在识别截图文字…"

        Task {
            let lines = await OCRService.shared.recognize(in: image)
            var parsed = RequirementParser.shared.parse(lines: lines)
            // 账号名优先用聊天窗口标题（比 OCR 更准确），读取不到时用 OCR 结果
            let windowTitle = pendingChatTitle ?? ChatWindowReader.currentChatTitle()
            pendingChatTitle = nil
            if let windowTitle, !windowTitle.isEmpty {
                parsed.accountName = windowTitle
            }
            let pngName = image.pngData.flatMap { TodoStore.shared.saveImagePNG($0) }
            let item = TodoItem(
                summary: parsed.summary,
                accountName: parsed.accountName,
                detail: parsed.detail,
                relatedItems: parsed.relatedItems,
                createdAt: parsed.createdAt ?? Date(),
                imagePath: pngName,
                sourceText: lines.map(\.text).joined(separator: "\n")
            )
            await MainActor.run {
                store.add(item)
                processing = false
                pasteButton.isEnabled = true
                screenshotButton.isEnabled = true
                statusLabel.stringValue = "已生成便签（识别 \(lines.count) 行文本）· 点击 ○ 完成 · 点击 × 删除"
            }
        }
    }

    // MARK: - 手动新建

    @objc func createManualNote() {
        let alert = NSAlert()
        alert.messageText = "新建便签"
        alert.informativeText = "输入待办内容（可留空标题，自动从内容取）"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        let titleField = NSTextField(string: "")
        titleField.placeholderString = "标题（可选）"
        titleField.frame = NSRect(x: 0, y: 0, width: 340, height: 26)
        let detailField = NSTextField(wrappingLabelWithString: "")
        detailField.placeholderString = "待办详情，一行一条"
        detailField.frame = NSRect(x: 0, y: 0, width: 340, height: 90)
        detailField.isEditable = true
        detailField.isSelectable = true
        detailField.isBordered = true
        detailField.drawsBackground = true
        detailField.font = .systemFont(ofSize: 12)

        stack.addArrangedSubview(titleField)
        stack.addArrangedSubview(detailField)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = titleField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let summary = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        let detail = detailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty || !summary.isEmpty else { return }

        let related = detail.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let item = TodoItem(
            summary: summary.isEmpty ? (related.first.map { String($0.prefix(24)) } ?? "手动便签") : summary,
            detail: detail,
            relatedItems: related,
            createdAt: Date()
        )
        store.add(item)
    }

    // MARK: - 其他

    @objc private func filterChanged() {
        filter = Filter(rawValue: filterControl.selectedSegment) ?? .all
        reload()
    }

    @objc private func toggleDesktopPanel() {
        desktopWidgetsVisible = desktopCheckbox.state == .on
        for panel in desktopWidgets.values {
            if desktopWidgetsVisible {
                panel.showWidget()
            } else {
                panel.orderOut(nil)
            }
        }
    }

    // MARK: - 桌面小组件

    /// 与数据同步：新增/完成/删除待办时，创建或移除对应小组件窗口
    private func syncDesktopWidgets() {
        let pending = store.items.filter { !$0.isCompleted }
        let ids = Set(pending.map { $0.id })
        // 移除已完成/已删除的小组件
        for (id, panel) in desktopWidgets where !ids.contains(id) {
            panel.orderOut(nil)
            desktopWidgets.removeValue(forKey: id)
        }
        // 为新待办创建小组件，默认从右上角依次向下排列
        var index = 0
        for item in pending {
            if desktopWidgets[item.id] == nil {
                let panel = DesktopWidgetPanel(item: item, mode: desktopWidgetMode)
                panel.onToggle = { [weak self] id in self?.store.toggle(id) }
                panel.onDelete = { [weak self] id in self?.store.delete(id) }
                panel.onPin = { [weak self] in self?.toggleDesktopWidgetMode() }
                panel.setDefaultColumnIndex(index)
                desktopWidgets[item.id] = panel
            }
            index += 1
        }
        // 应用整体显隐（桌面小组件复选框）
        for panel in desktopWidgets.values {
            if desktopWidgetsVisible { panel.showWidget() } else { panel.orderOut(nil) }
        }
    }

    /// 点击任意小组件图钉：全局切换 贴桌面 ⇄ 置顶
    private func toggleDesktopWidgetMode() {
        desktopWidgetMode = desktopWidgetMode == .desktop ? .floating : .desktop
        UserDefaults.standard.set(desktopWidgetMode.rawValue, forKey: "desktopPanelMode")
        for panel in desktopWidgets.values {
            panel.apply(mode: desktopWidgetMode)
        }
    }

    @objc func menuFilterAll() {
        filter = .all
        filterControl.selectedSegment = 0
        reload()
    }

    @objc func menuFilterPending() {
        filter = .pending
        filterControl.selectedSegment = 1
        reload()
    }

    @objc func menuFilterCompleted() {
        filter = .completed
        filterControl.selectedSegment = 2
        reload()
    }

    private func confirmDelete(_ id: String) {
        let alert = NSAlert()
        alert.messageText = "删除这张便签？"
        alert.informativeText = "删除后不可恢复（含截图）。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            store.delete(id)
        }
    }

    private func openImageDetail(_ path: String) {
        guard let url = TodoStore.shared.imageURL(for: path), let img = NSImage(contentsOf: url) else { return }
        // 复用已创建的查看窗口，只替换图片（窗口长期持有，点红叉仅隐藏）
        if let win = imageDetailWindow, let doc = imageDetailDoc {
            doc.setImage(img, minSize: imageDetailMinSize)
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "聊天截图"
        // 关键：窗口由属性长期持有；点红叉时仅隐藏不销毁（见 windowShouldClose），
        // 彻底避开「局部窗口被 ARC 释放 + 关闭动画引用已销毁窗口」的闪退
        win.isReleasedWhenClosed = false
        win.animationBehavior = .none
        win.delegate = self
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.contentView.postsBoundsChangedNotifications = true
        let doc = ImageCenterView(image: img, minSize: imageDetailMinSize)
        scroll.documentView = doc
        // 窗口缩放时保持图片居中
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { note in
            (note.object as? NSClipView)?.documentView?.needsLayout = true
        }
        win.contentView = scroll
        imageDetailWindow = win
        imageDetailDoc = doc
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var imageDetailMinSize: NSSize { NSSize(width: 600, height: 800) }

    // MARK: - 图片查看窗口：点红叉仅隐藏，避开窗口关闭动画崩溃

    private func dismissImageDetail() {
        imageDetailWindow?.orderOut(nil)
    }

    private func showMessage(_ msg: String, info: String) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText = info
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// MARK: - 辅助

/// 图片查看窗口关闭拦截：点红叉仅隐藏不销毁，避开窗口关闭动画的过度释放崩溃
extension MainViewController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === imageDetailWindow else { return true }
        sender.orderOut(nil)
        return false
    }
}

/// 图片查看文档视图：图片等比缩放适配窗口，并在可见区域内水平垂直居中；
/// 图片大于可见区域时保持原始缩放比例，可滚动查看（初始显示顶部）
final class ImageCenterView: NSView {
    private let imageView = NSImageView()
    private var imageSize: NSSize = .zero

    override var isFlipped: Bool { true }

    init(image: NSImage, minSize: NSSize) {
        super.init(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        setImage(image, minSize: minSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 设置图片：等比缩放到「宽 ≤ minSize.width 且 高 ≤ minSize.height」（不放大）
    func setImage(_ image: NSImage, minSize: NSSize) {
        var s = image.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = min(1, min(minSize.width / s.width, minSize.height / s.height))
        s.width *= scale
        s.height *= scale
        imageSize = s
        imageView.image = image
        relayout()
    }

    override func layout() {
        super.layout()
        relayout()
    }

    /// 根据可见区域重排：文档视图撑满可见区域（图片小时居中），超过时按内容滚动
    private func relayout() {
        guard let clip = superview as? NSClipView else { return }
        let vis = clip.bounds.size
        frame.size = NSSize(width: max(imageSize.width, vis.width), height: max(imageSize.height, vis.height))
        let x = (frame.width - imageSize.width) / 2
        let y = (frame.height - imageSize.height) / 2
        imageView.frame = NSRect(x: max(x, 0), y: max(y, 0), width: imageSize.width, height: imageSize.height)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 图片拖放目标：把截图文件拖入主窗口即生成便签
final class DragDropView: NSView {
    var onImageDrop: ((NSImage) -> Void)?

    private let overlay = NSView()
    private let label = NSTextField(labelWithString: "松开以生成便签")

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "webp", "bmp", "heic", "heif"]

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])

        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        overlay.layer?.cornerRadius = 12
        overlay.isHidden = true
        overlay.autoresizingMask = [.width, .height]
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.autoresizingMask = [.width]
        overlay.addSubview(label)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        overlay.frame = bounds
        label.frame = NSRect(x: 0, y: bounds.midY - 20, width: bounds.width, height: 40)
    }

    // MARK: - NSDraggingDestination

    private func containsImage(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }
        return urls.contains { Self.imageExts.contains($0.pathExtension.lowercased()) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsImage(sender) else { return [] }
        overlay.isHidden = false
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        containsImage(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        overlay.isHidden = true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        overlay.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        overlay.isHidden = true
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first(where: { Self.imageExts.contains($0.pathExtension.lowercased()) }),
              let image = NSImage(contentsOf: url)
        else { return false }
        onImageDrop?(image)
        return true
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
