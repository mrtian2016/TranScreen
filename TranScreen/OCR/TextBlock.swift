import CoreGraphics
import Foundation

struct TextBlock: Identifiable, Sendable {
    let id: UUID
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    var isVertical: Bool

    init(from result: OCREngine.OCRResult) {
        self.id = UUID()
        self.text = result.text
        self.boundingBox = result.boundingBox
        self.confidence = result.confidence
        self.isVertical = result.boundingBox.width < result.boundingBox.height * 0.5
    }
}

struct MergedTextBlock: Identifiable, Sendable {
    let id: UUID
    let text: String
    let boundingBox: CGRect
    let lines: [TextBlock]
    var isVertical: Bool

    init(lines: [TextBlock]) {
        self.id = UUID()
        self.lines = lines
        self.isVertical = lines.first?.isVertical ?? false
        self.text = lines.map(\.text).joined(separator: isVertical ? "" : " ")
        self.boundingBox = lines.reduce(CGRect.null) { $0.union($1.boundingBox) }
    }
}
