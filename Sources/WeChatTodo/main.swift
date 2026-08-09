import AppKit

// AppDelegate 必须全局持有：NSApplication.delegate 是 unowned(unsafe) 弱引用，
// 若用局部变量，-O 优化会在 app.run() 前提前释放它，导致所有 delegate 回调野指针崩溃。
private let appDelegate = AppDelegate()

let app = NSApplication.shared
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
