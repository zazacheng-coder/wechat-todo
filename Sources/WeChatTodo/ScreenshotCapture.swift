import AppKit
import CoreGraphics

/// 读取当前前台聊天软件的会话窗口标题（对方账号名/群名）
/// 依赖屏幕录制权限（截图功能已要求，未授权时返回 nil 回退 OCR 识别）
enum ChatWindowReader {
    static let chatBundleIDs: Set<String> = [
        "com.tencent.xinWeChat", // 微信
        "com.tencent.qq",        // QQ
        "com.laiwang.DingTalk",  // 钉钉
        "com.bytedance.lark",    // 飞书
    ]
    /// 各聊天软件主界面/无关窗口的标题，需排除
    private static let excludedTitles: Set<String> = ["微信", "QQ", "钉钉", "飞书"]

    /// 当前前台应用若是聊天软件，返回其最前面的会话窗口标题；否则返回 nil
    static func currentChatTitle() -> String? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              chatBundleIDs.contains(bundleID)
        else { return nil }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let pid = front.processIdentifier
        // 返回列表按 z-order 排列（最前窗口在前）
        for window in list {
            guard window[kCGWindowOwnerPID as String] as? Int32 == pid else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue } // 只取普通窗口层
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.3 else { continue }
            guard let title = window[kCGWindowName as String] as? String, !title.isEmpty else { continue }
            if excludedTitles.contains(title) { continue } // 排除主界面
            return title
        }
        return nil
    }
}

/// 内置截图服务：抓取主屏幕 + 检测屏幕录制权限
enum ScreenshotService {
    /// 是否已获得屏幕录制权限（macOS 10.15+）
    static func hasPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    /// 抓取主屏幕（未授权时返回全黑图，需用 hasPermission 提前检查）
    static func captureMainDisplay() -> CGImage? {
        guard let displayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return CGDisplayCreateImage(displayID)
    }

    /// 按选区裁剪图像（rect 为 points 坐标，自动乘屏幕缩放系数）
    static func crop(_ image: NSImage, rect: NSRect, scale: CGFloat) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let px = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard px.width >= 2, px.height >= 2, let cropped = cg.cropping(to: px) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}

/// 全屏框选窗口（盖住整个屏幕，类似系统截图工具）
final class CaptureOverlayWindow: NSWindow {
    /// 强持有最近一次使用的覆盖窗口。
    /// 崩溃根因：窗口关闭/取消时被提前释放，而 AppKit 的 _NSWindowTransformAnimation
    /// （层级切换/关闭动画）仍引用它，动画随 CA 事务提交时过度释放已销毁的窗口 → 闪退。
    /// 保持窗口存活（直到下次截图替换）可保证动画引用时窗口一定存在。
    private static var keepAlive: CaptureOverlayWindow?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, image: NSImage, onCapture: @escaping (NSImage) -> Void, onCancel: @escaping () -> Void) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        // 防止窗口关闭/取消时被 AppKit 额外 release（ARC 下过度释放崩溃）
        isReleasedWhenClosed = false
        // 截图覆盖层不需要任何显示/关闭动画
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        contentView = CaptureOverlayView(
            frame: screen.frame,
            image: image,
            scale: screen.backingScaleFactor,
            onCapture: onCapture,
            onCancel: onCancel
        )
        // 保持自身存活，避免 transform 动画引用已释放的窗口（见 keepAlive 注释）
        Self.keepAlive = self
    }
}

/// 框选交互视图（isFlipped 与屏幕坐标一致：原点左上）
final class CaptureOverlayView: NSView {
    private let image: NSImage
    private let scale: CGFloat
    private let onCapture: (NSImage) -> Void
    private let onCancel: () -> Void

    private var selection: NSRect?
    private var dragStart: NSPoint?
    private var finished = false
    private var toolBar: NSVisualEffectView!

    init(frame: NSRect, image: NSImage, scale: CGFloat, onCapture: @escaping (NSImage) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.scale = scale
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(frame: frame)
        buildToolBar()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func buildToolBar() {
        toolBar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 0, height: 44))
        toolBar.material = .hudWindow
        toolBar.wantsLayer = true
        toolBar.layer?.cornerRadius = 10
        toolBar.layer?.masksToBounds = true

        let hint = NSTextField(labelWithString: "拖动框选要记录的区域 · Esc 取消 · 回车确认")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .white
        hint.frame = NSRect(x: 14, y: 12, width: 300, height: 20)
        toolBar.addSubview(hint)

        let cancelBtn = NSButton(title: "取消 (Esc)", target: self, action: #selector(cancelTapped))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.font = .systemFont(ofSize: 12)
        cancelBtn.frame = NSRect(x: toolBar.bounds.width - 180, y: 7, width: 80, height: 30)
        toolBar.addSubview(cancelBtn)

        let okBtn = NSButton(title: "确认 (⏎)", target: self, action: #selector(confirmTapped))
        okBtn.bezelStyle = .rounded
        okBtn.keyEquivalent = "\r"
        okBtn.font = .systemFont(ofSize: 12)
        okBtn.frame = NSRect(x: toolBar.bounds.width - 92, y: 7, width: 80, height: 30)
        toolBar.addSubview(okBtn)

        addSubview(toolBar)
        layoutToolBar()
    }

    private func layoutToolBar() {
        let w: CGFloat = 300
        toolBar.frame = NSRect(x: (bounds.width - w) / 2, y: bounds.height - 70, width: w, height: 44)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 全屏截图
        image.draw(in: bounds)

        // 选区外遮罩
        let sel = selection ?? .zero
        let hasSel = selection != nil && sel.width > 0 && sel.height > 0
        let mask = NSColor(calibratedWhite: 0, alpha: 0.45)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        mask.setFill()
        if hasSel {
            // 用奇偶规则抠出选区
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: sel))
            path.windingRule = .evenOdd
            path.fill()
        } else {
            NSRect(origin: .zero, size: bounds.size).fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        // 选区框 + 尺寸
        if hasSel {
            let border = NSBezierPath(rect: sel)
            border.lineWidth = 1.5
            NSColor.white.setStroke()
            border.stroke()

            let sizeText = "\(Int(sel.width)) × \(Int(sel.height))"
            let attr: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
            let str = NSAttributedString(string: sizeText, attributes: attr)
            let textRect = NSRect(x: sel.minX, y: sel.minY - 22, width: str.size().width + 10, height: 18)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()
            str.draw(at: NSPoint(x: textRect.minX + 5, y: textRect.minY + 2))
        }
    }

    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragStart = p
        selection = NSRect(x: p.x, y: p.y, width: 0, height: 0)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let start = dragStart else { return }
        let rect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        selection = rect
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // 仅结束拖动，等待用户确认
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            cancelTapped()
        case 36, 76: // Return
            confirmTapped()
        default:
            super.keyDown(with: event)
        }
    }

    @objc private func cancelTapped() {
        guard !finished else { return }
        finished = true
        window?.orderOut(nil)
        onCancel()
    }

    @objc private func confirmTapped() {
        guard !finished else { return }
        guard let sel = selection, sel.width >= 2, sel.height >= 2 else {
            NSSound.beep()
            return
        }
        guard let cropped = ScreenshotService.crop(image, rect: sel, scale: scale) else {
            NSSound.beep()
            return
        }
        finished = true
        window?.orderOut(nil)
        onCapture(cropped)
    }
}
