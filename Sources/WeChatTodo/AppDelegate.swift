import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var mainVC: MainViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainVC = MainViewController()
        buildMainMenu(target: mainVC)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "便签待办"
        window.minSize = NSSize(width: 720, height: 480)
        // 关键：防止 AppKit 在关闭窗口时额外 release（ARC 下导致窗口悬空、reopen 崩溃）
        window.isReleasedWhenClosed = false
        // 禁用显示/关闭的 transform 动画：截图时主窗口 orderOut→makeKeyAndOrderFront 与
        // CGDisplayCreateImage 截屏交错会触发 _NSWindowTransformAnimation 过度释放崩溃
        window.animationBehavior = .none
        window.contentViewController = mainVC
        window.center()
        window.setFrameAutosaveName("WeChatTodoMainWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 桌面便签常驻：关闭主窗口不退出，仅隐藏
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // 窗口已关闭但对象仍存活（isReleasedWhenClosed = false），安全重开
            if let w = window {
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }

    // MARK: - 菜单

    private func buildMainMenu(target: MainViewController) {
        let mainMenu = NSMenu()

        // 应用菜单
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 便签待办", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 便签待办", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 便签待办", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // 文件菜单
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        let newNote = NSMenuItem(title: "新建便签", action: #selector(MainViewController.createManualNote), keyEquivalent: "n")
        newNote.target = target
        fileMenu.addItem(newNote)
        fileItem.submenu = fileMenu

        // 编辑菜单（粘贴截图）
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        let paste = NSMenuItem(title: "粘贴截图生成便签", action: #selector(MainViewController.pasteFromClipboard(_:)), keyEquivalent: "v")
        paste.target = target
        editMenu.addItem(paste)
        editItem.submenu = editMenu

        // 显示菜单（筛选）
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "显示")
        let allItem = NSMenuItem(title: "全部", action: #selector(MainViewController.menuFilterAll), keyEquivalent: "")
        let pendingItem = NSMenuItem(title: "仅待办", action: #selector(MainViewController.menuFilterPending), keyEquivalent: "")
        let completedItem = NSMenuItem(title: "仅已完成", action: #selector(MainViewController.menuFilterCompleted), keyEquivalent: "")
        allItem.target = target
        pendingItem.target = target
        completedItem.target = target
        viewMenu.addItem(allItem)
        viewMenu.addItem(pendingItem)
        viewMenu.addItem(completedItem)
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }
}
