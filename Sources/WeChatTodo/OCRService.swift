import AppKit
import Vision

/// 基于 Vision 框架的本地 OCR 服务（完全离线）
final class OCRService {
    static let shared = OCRService()

    /// 一行识别结果（坐标归一化 0~1，origin 在左下角）
    struct Line {
        let text: String
        /// 归一化 y（0=底部，1=顶部）
        let y: Double
        /// 归一化 x（0=左侧，1=右侧）
        let x: Double
    }

    /// 同步执行 OCR，返回按阅读顺序（从上到下）排列的文本行
    func recognize(in image: NSImage) async -> [Line] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { request, _ in
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                let lines: [Line] = results.compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return Line(text: top.string, y: Double(obs.boundingBox.midY), x: Double(obs.boundingBox.midX))
                }
                // y 从下往上，翻转后得到从上往下的阅读顺序
                cont.resume(returning: lines.sorted { $0.y > $1.y })
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
