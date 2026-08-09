#!/usr/bin/env swift
import AppKit
import CoreGraphics

/// 生成 1024×1024 便签待办应用图标 PNG
/// 视觉与 NoteCardView 保持一致：黄纸 + 右上角折角 + 文字线 + 绿色对勾

let size: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("无法创建位图上下文\n".data(using: .utf8)!)
    exit(1)
}

// 透明背景
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// 便签主体（圆角矩形）
let margin: CGFloat = 120
let noteRect = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
let cornerRadius: CGFloat = 60

// 阴影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 60, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
let notePath = CGPath(roundedRect: noteRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(notePath)
ctx.setFillColor(CGColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1.0)) // 与 noteBackground 一致
ctx.fillPath()
ctx.restoreGState()

// 右上角折角（露出背面浅色）
let foldSize: CGFloat = 180
let foldPath = CGMutablePath()
foldPath.move(to: CGPoint(x: noteRect.maxX - foldSize, y: noteRect.maxY))
foldPath.addLine(to: CGPoint(x: noteRect.maxX, y: noteRect.maxY))
foldPath.addLine(to: CGPoint(x: noteRect.maxX, y: noteRect.maxY - foldSize))
foldPath.closeSubpath()
ctx.addPath(foldPath)
ctx.setFillColor(CGColor(red: 0.94, green: 0.88, blue: 0.66, alpha: 1.0)) // 折角背面略深
ctx.fillPath()

// 折角描边（区分折痕）
ctx.addPath(foldPath)
ctx.setStrokeColor(CGColor(red: 0.78, green: 0.72, blue: 0.5, alpha: 0.6))
ctx.setLineWidth(2)
ctx.strokePath()

// 文字线条（灰色横线模拟文本）
let lineColor = CGColor(red: 0.4, green: 0.35, blue: 0.25, alpha: 0.35)
ctx.setStrokeColor(lineColor)
ctx.setLineWidth(8)
ctx.setLineCap(.round)

let lineLeft = noteRect.minX + 90
let lineRight = noteRect.maxX - 90
let lineStartY = noteRect.maxY - 200
let lineHeight: CGFloat = 70

for i in 0..<4 {
    let y = lineStartY - CGFloat(i) * lineHeight
    var right = lineRight
    if i == 3 { right = lineLeft + (lineRight - lineLeft) * 0.6 } // 最后一行短
    ctx.move(to: CGPoint(x: lineLeft, y: y))
    ctx.addLine(to: CGPoint(x: right, y: y))
    ctx.strokePath()
}

// 绿色对勾圆（与 CircularCheckControl 一致），放在便签右下
let checkDiameter: CGFloat = 260
let checkRect = CGRect(
    x: noteRect.maxX - checkDiameter - 70,
    y: noteRect.minY + 70,
    width: checkDiameter,
    height: checkDiameter
)
let checkInset = checkRect.insetBy(dx: 20, dy: 20)
let checkPath = CGPath(ellipseIn: checkInset, transform: nil)
ctx.addPath(checkPath)
ctx.setFillColor(CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0)) // systemGreen
ctx.fillPath()

// 白色对勾（左上 → 中下 → 右上）
let tick = CGMutablePath()
tick.move(to: CGPoint(x: checkInset.minX + 0.26 * checkInset.width, y: checkInset.midY + 0.2 * checkInset.height))
tick.addLine(to: CGPoint(x: checkInset.minX + 0.44 * checkInset.width, y: checkInset.midY - 0.24 * checkInset.height))
tick.addLine(to: CGPoint(x: checkInset.maxX - 0.2 * checkInset.width, y: checkInset.midY + 0.2 * checkInset.height))
ctx.addPath(tick)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(28)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

// 输出 PNG
guard let img = ctx.makeImage() else {
    FileHandle.standardError.write("无法生成图像\n".data(using: .utf8)!)
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: img)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("无法编码 PNG\n".data(using: .utf8)!)
    exit(1)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon_1024.png"
try? pngData.write(to: URL(fileURLWithPath: outPath))
print("已生成: \(outPath)")
