import CoreGraphics

struct LineGeometry: Sendable {
    let leftEdge: CGFloat
    let rightEdge: CGFloat
    let width: CGFloat

    init(left: CGFloat, right: CGFloat) {
        self.leftEdge = left
        self.rightEdge = right
        self.width = right - left
    }
}

struct EdgeDetector {

    /// Detect per-line left/right edges from observation bounding boxes.
    /// Each observation is a recognized text line.
    func detectLineEdges(blocks: [TextBlock]) -> LineGeometry? {
        guard !blocks.isEmpty else { return nil }

        let leftEdge = blocks.map(\.boundingBox.origin.x).min() ?? 0
        let rightEdge = blocks.map { $0.boundingBox.origin.x + $0.boundingBox.width }.max() ?? 0
        return LineGeometry(left: leftEdge, right: rightEdge)
    }

    /// Detect paragraph-level right edge (max extent across all lines in the paragraph).
    func detectParagraphRightEdge(blocks: [TextBlock]) -> CGFloat {
        guard !blocks.isEmpty else { return 1.0 }
        return blocks.map { $0.boundingBox.origin.x + $0.boundingBox.width }.max() ?? 1.0
    }
}
