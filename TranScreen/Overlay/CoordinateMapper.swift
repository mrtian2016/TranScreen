import CoreGraphics
import AppKit

struct CoordinateMapper {
    let screen: NSScreen
    let captureRegion: CGRect
    let imageSize: CGSize
    let scaleFactor: CGFloat

    init(
        screen: NSScreen = NSScreen.main ?? NSScreen.screens[0],
        captureRegion: CGRect,
        imageSize: CGSize
    ) {
        self.screen = screen
        self.captureRegion = captureRegion
        self.imageSize = imageSize
        self.scaleFactor = screen.backingScaleFactor
    }

    // Vision 归一化 boundingBox (左下角原点) → SwiftUI 屏幕坐标 (左上角原点)
    func mapToSwiftUI(visionBox: CGRect) -> CGRect {
        let screenHeight = screen.frame.height

        // 步骤1: 归一化 → 像素 (Vision Y 向上)
        let pixelX = visionBox.origin.x * imageSize.width
        let pixelY = visionBox.origin.y * imageSize.height
        let pixelW = visionBox.width * imageSize.width
        let pixelH = visionBox.height * imageSize.height

        // 步骤2: 像素 → 逻辑点
        let pointX = pixelX / scaleFactor
        let pointY = pixelY / scaleFactor
        let pointW = pixelW / scaleFactor
        let pointH = pixelH / scaleFactor

        // 步骤3: 图像坐标 → 屏幕坐标 (AppKit Y 向上)
        let screenX = captureRegion.origin.x + pointX
        let screenY = captureRegion.origin.y + pointY

        // 步骤4: AppKit → SwiftUI (Y 轴翻转)
        let swiftuiY = screenHeight - screenY - pointH

        return CGRect(x: screenX, y: swiftuiY, width: pointW, height: pointH)
    }

    /// Calculate adaptive font size from per-line OCR bounding boxes (Vision normalized).
    /// Each observation is one line of text. Uses median (P50) of line heights so two
    /// blocks with the same actual font size — even if they have different line counts —
    /// resolve to the same font size, while title vs body still come out distinct.
    func adaptiveFontSize(forLineBoxes boxes: [CGRect]) -> CGFloat {
        guard !boxes.isEmpty else { return 14 }
        let heights = boxes.map { mapToSwiftUI(visionBox: $0).height }.sorted()
        let median = heights[heights.count / 2]
        return max(9, min(48, median * 0.85))
    }
}
