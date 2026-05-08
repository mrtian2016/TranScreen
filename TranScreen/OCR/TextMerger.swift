import CoreGraphics

struct TextMerger {
    var lineSpacingThreshold: CGFloat = 1.5

    func merge(blocks: [TextBlock]) -> [MergedTextBlock] {
        guard !blocks.isEmpty else { return [] }

        let sorted = blocks.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        var groups: [[TextBlock]] = []
        var currentGroup: [TextBlock] = [sorted[0]]

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]

            let prevBottom = prev.boundingBox.origin.y
            let prevHeight = prev.boundingBox.height
            let currTop = curr.boundingBox.origin.y + curr.boundingBox.height
            let gap = prevBottom - currTop
            let threshold = prevHeight * lineSpacingThreshold

            if gap < threshold && hasHorizontalOverlap(prev.boundingBox, curr.boundingBox) {
                currentGroup.append(curr)
            } else {
                groups.append(currentGroup)
                currentGroup = [curr]
            }
        }
        groups.append(currentGroup)

        return groups.map { MergedTextBlock(lines: $0) }
    }

    private func hasHorizontalOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlapWidth = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let minWidth = min(a.width, b.width)
        return overlapWidth > minWidth * 0.3
    }
}
