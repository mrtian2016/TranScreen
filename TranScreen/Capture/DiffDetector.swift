import CoreGraphics
import AppKit

actor DiffDetector {
    private var previousPixelData: [UInt8]?
    private let gridSize = 16
    private let changeThreshold: Float = 0.05

    func detectChangedRegions(current: CGImage) -> [CGRect] {
        let width = current.width
        let height = current.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(current, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let prev = previousPixelData, prev.count == pixelData.count else {
            previousPixelData = pixelData
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        let cellW = width / gridSize
        let cellH = height / gridSize
        var dirtyRects: [CGRect] = []

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = col * cellW
                let y = row * cellH
                var totalDiff: Float = 0
                let pixelCount = Float(cellW * cellH)

                for py in y..<(y + cellH) {
                    for px in x..<(x + cellW) {
                        let idx = py * bytesPerRow + px * bytesPerPixel
                        if idx + 2 < pixelData.count {
                            let dr = abs(Int(pixelData[idx]) - Int(prev[idx]))
                            let dg = abs(Int(pixelData[idx + 1]) - Int(prev[idx + 1]))
                            let db = abs(Int(pixelData[idx + 2]) - Int(prev[idx + 2]))
                            totalDiff += Float(dr + dg + db) / (255.0 * 3.0)
                        }
                    }
                }

                if totalDiff / pixelCount > changeThreshold {
                    dirtyRects.append(CGRect(
                        x: CGFloat(col) / CGFloat(gridSize),
                        y: CGFloat(row) / CGFloat(gridSize),
                        width: 1.0 / CGFloat(gridSize),
                        height: 1.0 / CGFloat(gridSize)
                    ))
                }
            }
        }

        previousPixelData = pixelData
        return mergeAdjacentRects(dirtyRects)
    }

    func reset() {
        previousPixelData = nil
    }

    private func mergeAdjacentRects(_ rects: [CGRect]) -> [CGRect] {
        guard !rects.isEmpty else { return [] }
        var merged: [CGRect] = []
        var remaining = rects

        while !remaining.isEmpty {
            var current = remaining.removeFirst()
            var didMerge = true
            while didMerge {
                didMerge = false
                remaining = remaining.filter { rect in
                    if current.intersects(rect.insetBy(dx: -0.01, dy: -0.01)) {
                        current = current.union(rect)
                        didMerge = true
                        return false
                    }
                    return true
                }
            }
            merged.append(current)
        }
        return merged
    }
}
