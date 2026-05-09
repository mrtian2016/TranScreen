import CoreGraphics

enum BackgroundSampler {
    /// Sample perimeter pixels of a Vision-normalized bounding box to extract
    /// the exact average background color.
    /// - Returns: (r, g, b) in 0...1 range
    static func sampleBackgroundColor(image: CGImage, normalizedBox: CGRect) -> (r: Double, g: Double, b: Double) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        let px = (normalizedBox.origin.x * imgW).rounded()
        let py = ((1.0 - normalizedBox.origin.y - normalizedBox.height) * imgH).rounded()
        let pw = (normalizedBox.width * imgW).rounded()
        let ph = (normalizedBox.height * imgH).rounded()

        // Wider margin (3px) gives the perimeter sampler more pure-bg pixels to work
        // with on tight OCR boxes around small text, where the previous 2px margin
        // sometimes dipped into the ink itself.
        let margin: CGFloat = 3
        let sampleX = max(0, px - margin)
        let sampleY = max(0, py - margin)
        let sampleW = min(imgW - sampleX, pw + margin * 2)
        let sampleH = min(imgH - sampleY, ph + margin * 2)

        let sampleRect = CGRect(x: sampleX, y: sampleY, width: sampleW, height: sampleH)
        guard sampleRect.width > 1, sampleRect.height > 1,
              let cropped = image.cropping(to: sampleRect) else {
            return (1, 1, 1)
        }

        return sampleEdges(cropped)
    }

    /// Whether the given background color should use dark text (for contrast).
    static func isLight(_ r: Double, _ g: Double, _ b: Double) -> Bool {
        (0.299 * r + 0.587 * g + 0.114 * b) > 0.5
    }

    /// Sample the dominant text color from the interior of a Vision-normalized bounding box.
    /// Filters pixels by distance from the *known* background color (not from box-mean
    /// luminance, which on a white-bg/black-ink line gets pulled high enough that the
    /// white bg pixels themselves still cross the threshold and outvote the ink).
    /// Survivors are HSV-quantized to (12 × 4 × 4) buckets; the majority bucket's mean
    /// RGB is returned.
    static func sampleTextColor(
        image: CGImage,
        normalizedBox: CGRect,
        background: (r: Double, g: Double, b: Double)
    ) -> (r: Double, g: Double, b: Double) {
        sampleTextColor(image: image, normalizedBoxes: [normalizedBox], background: background)
    }

    /// Per-line sampling then dominant-color merge.
    /// Samples each line independently and aggregates votes in the same HSV bucket
    /// space, so a paragraph that is mostly black + a few blue pixels resolves to black.
    static func sampleTextColor(
        image: CGImage,
        normalizedBoxes: [CGRect],
        background: (r: Double, g: Double, b: Double)
    ) -> (r: Double, g: Double, b: Double) {
        let bgR = Int(background.r * 255), bgG = Int(background.g * 255), bgB = Int(background.b * 255)
        var votes: [Int: (r: Int, g: Int, b: Int, count: Int)] = [:]
        for box in normalizedBoxes {
            collectTextPixelVotes(image: image, normalizedBox: box, bgR: bgR, bgG: bgG, bgB: bgB, into: &votes)
        }
        guard let winner = votes.max(by: { $0.value.count < $1.value.count })?.value, winner.count > 0 else {
            // Nothing stood out from background — fall back to opposite-of-bg for legibility.
            return isLight(background.r, background.g, background.b) ? (0, 0, 0) : (1, 1, 1)
        }
        let n = Double(winner.count)
        return (Double(winner.r) / n / 255.0, Double(winner.g) / n / 255.0, Double(winner.b) / n / 255.0)
    }

    /// Collect HSV-bucketed votes from pixels far enough from the background color.
    private static func collectTextPixelVotes(
        image: CGImage,
        normalizedBox: CGRect,
        bgR: Int, bgG: Int, bgB: Int,
        into votes: inout [Int: (r: Int, g: Int, b: Int, count: Int)]
    ) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        let px = (normalizedBox.origin.x * imgW).rounded()
        let py = ((1.0 - normalizedBox.origin.y - normalizedBox.height) * imgH).rounded()
        let pw = (normalizedBox.width * imgW).rounded()
        let ph = (normalizedBox.height * imgH).rounded()

        let insetX = pw * 0.15
        let insetY = ph * 0.15
        let sampleX = max(0, px + insetX)
        let sampleY = max(0, py + insetY)
        let sampleW = max(1, pw - insetX * 2)
        let sampleH = max(1, ph - insetY * 2)

        let sampleRect = CGRect(x: sampleX, y: sampleY, width: sampleW, height: sampleH)
        guard sampleRect.width > 2, sampleRect.height > 2,
              let cropped = image.cropping(to: sampleRect) else { return }

        let w = cropped.width
        let h = cropped.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bpp = 4
        let bpr = w * bpp
        var pixels = [UInt8](repeating: 0, count: h * bpr)

        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Squared Euclidean distance threshold from the bg RGB. 60² covers anti-aliased
        // edge pixels (which tend to be ~half-way between ink and bg) but rejects
        // background noise. Tuned conservatively — too small and we'll vote AA pixels;
        // too large and thin/light text gets dropped entirely.
        let threshold2 = 60 * 60

        for y in 0..<h {
            for x in 0..<w {
                let off = y * bpr + x * bpp
                let r = Int(pixels[off]), g = Int(pixels[off + 1]), b = Int(pixels[off + 2])
                let dr = r - bgR, dg = g - bgG, db = b - bgB
                let d2 = dr * dr + dg * dg + db * db
                if d2 < threshold2 { continue }
                let bucket = hsvBucket(r: r, g: g, b: b)
                var entry = votes[bucket] ?? (0, 0, 0, 0)
                entry.r += r; entry.g += g; entry.b += b; entry.count += 1
                votes[bucket] = entry
            }
        }
    }

    /// HSV bucket id: 12 hue × 4 sat × 4 val = 192 buckets.
    private static func hsvBucket(r: Int, g: Int, b: Int) -> Int {
        let rf = Double(r) / 255.0, gf = Double(g) / 255.0, bf = Double(b) / 255.0
        let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
        let delta = maxC - minC
        let v = maxC
        let s = maxC == 0 ? 0 : delta / maxC
        var h: Double = 0
        if delta > 0 {
            if maxC == rf {
                h = ((gf - bf) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == gf {
                h = ((bf - rf) / delta) + 2
            } else {
                h = ((rf - gf) / delta) + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        let hb = min(11, Int(h / 30))
        let sb = min(3, Int(s * 4))
        let vb = min(3, Int(v * 4))
        return hb * 16 + sb * 4 + vb
    }

    private static func sampleEdges(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
        let w = image.width
        let h = image.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)

        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (1, 1, 1) }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Walk perimeter and collect each channel separately. Median per channel
        // is robust to the few ink/anti-aliased pixels that leak into the perimeter
        // when the OCR box hugs the text tightly (which happens a lot on small text
        // where the previous mean-based estimator was getting pulled toward the
        // ink color).
        var rs: [UInt8] = []
        var gs: [UInt8] = []
        var bs: [UInt8] = []
        rs.reserveCapacity((w + h) * 2)
        gs.reserveCapacity((w + h) * 2)
        bs.reserveCapacity((w + h) * 2)

        func collect(_ off: Int) {
            rs.append(pixels[off])
            gs.append(pixels[off + 1])
            bs.append(pixels[off + 2])
        }

        // Sample two outermost rows at top and bottom, two outermost cols at left/right.
        // Two rows/cols give enough perimeter coverage that stray ink pixels never
        // dominate, while still being cheap.
        let topRows = [0, min(1, h - 1)]
        let bottomRows = [h - 1, max(0, h - 2)]
        let leftCols = [0, min(1, w - 1)]
        let rightCols = [w - 1, max(0, w - 2)]

        for y in topRows + bottomRows where y >= 0 && y < h {
            for x in 0..<w { collect(y * bytesPerRow + x * bytesPerPixel) }
        }
        for x in leftCols + rightCols where x >= 0 && x < w {
            for y in 0..<h { collect(y * bytesPerRow + x * bytesPerPixel) }
        }

        guard !rs.isEmpty else { return (1, 1, 1) }
        rs.sort(); gs.sort(); bs.sort()
        let medR = rs[rs.count / 2]
        let medG = gs[gs.count / 2]
        let medB = bs[bs.count / 2]
        return (Double(medR) / 255.0, Double(medG) / 255.0, Double(medB) / 255.0)
    }
}
