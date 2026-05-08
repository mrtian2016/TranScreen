import CoreGraphics
import Foundation

struct TranslatedBlock: Identifiable, Sendable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let visionBoundingBox: CGRect
    var captureRegion: CGRect = .zero
    let isVertical: Bool
    var screenRect: CGRect = .zero
    var fontSize: CGFloat = 14

    init(
        originalText: String,
        translatedText: String,
        visionBoundingBox: CGRect,
        isVertical: Bool = false
    ) {
        self.id = UUID()
        self.originalText = originalText
        self.translatedText = translatedText
        self.visionBoundingBox = visionBoundingBox
        self.isVertical = isVertical
    }
}
