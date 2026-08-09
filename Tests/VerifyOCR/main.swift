import AppKit

// 端到端验证：绘制模拟微信聊天截图 → Vision OCR → 规则解析
func makeTestImage() -> NSImage {
    let size = NSSize(width: 750, height: 900)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()

    func draw(_ s: String, y: CGFloat, size: CGFloat = 26, bold: Bool = false, color: NSColor = .black) {
        let f = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: para]
        s.draw(in: NSRect(x: 0, y: y, width: 750, height: size + 20), withAttributes: attrs)
    }

    draw("8月4日 上午 9:30", y: 780, size: 24, color: .gray)
    draw("张伟：", y: 710, size: 28, bold: true, color: NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.9, alpha: 1))
    draw("这周需要整理下季度销售数据，麻烦周五前给我一版", y: 660, size: 28)
    draw("李娜：", y: 580, size: 28, bold: true, color: NSColor(calibratedRed: 0.1, green: 0.6, blue: 0.2, alpha: 1))
    draw("好的，我再补充一下各项目的进度统计", y: 530, size: 28)
    draw("上午 10:15", y: 440, size: 24, color: .gray)
    draw("张伟：", y: 380, size: 28, bold: true, color: NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.9, alpha: 1))
    draw("另外下周安排一次评审会议", y: 330, size: 28)

    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: size)
    img.addRepresentation(rep)
    return img
}

let image = makeTestImage()
let sem = DispatchSemaphore(value: 0)
var failed = false

func check(_ cond: Bool, _ name: String) {
    if cond { print("PASS  \(name)") } else { failed = true; print("FAIL  \(name)") }
}

Task {
    let lines = await OCRService.shared.recognize(in: image)
    print("== OCR 识别 \(lines.count) 行 ==")
    for l in lines { print("   \(l.text)") }
    let r = RequirementParser.shared.parse(lines: lines)
    print("== 解析结果 ==")
    print("   createdAt: \(r.createdAt?.description ?? "nil")")
    print("   summary:   \(r.summary)")
    print("   related:   \(r.relatedItems)")

    let text = lines.map(\.text).joined(separator: "\n")
    check(text.contains("销售数据"), "OCR 识别出需求内容")
    check(text.contains("9:30") || text.contains("9:3") || text.contains("9 30"), "OCR 识别出时间")
    check(r.summary.contains("整理") || r.summary.contains("销售"), "摘要提取: \(r.summary)")
    check(r.relatedItems.count >= 1, "相关需求提取: \(r.relatedItems)")
    check(r.createdAt != nil, "需求产生时间生成")
    sem.signal()
}

sem.wait()
exit(failed ? 1 : 0)
