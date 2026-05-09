import SwiftUI

struct TranslationOverlayView: View {
    let blocks: [TranslatedBlock]
    let opacity: Double
    let showingOriginal: Bool
    var debugCapturedSize: CGSize = .zero
    var debugOCRCount: Int = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(opacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // 调试角标
                if !blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("blocks: \(blocks.count)  ocr: \(debugOCRCount)")
                        Text("captured: \(Int(debugCapturedSize.width))×\(Int(debugCapturedSize.height))px")
                        Text("geo: \(Int(geo.size.width))×\(Int(geo.size.height))")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .padding(6)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(4)
                    .position(x: 140, y: 40)
                    .allowsHitTesting(false)
                }

                ForEach(blocks) { block in
                    let w = max(30, edgeAwareWidth(for: block))
                    let h = max(1, block.screenRect.height + 2)
                    translationLabel(for: block)
                        .frame(width: w, height: h, alignment: alignmentForBlock(block))
                        .background(backgroundForBlock(block))
                        .allowsHitTesting(false)
                        // Anchor frame's top-leading corner at the OCR box's top-left
                        // so the translation starts at exactly the original text's
                        // start position (instead of being centered, which shifts
                        // it whenever frame width ≠ OCR box width).
                        .position(
                            x: clamp(block.screenRect.minX + w / 2, min: 0, max: geo.size.width),
                            y: clamp(block.screenRect.minY - 1 + h / 2, min: 0, max: geo.size.height)
                        )
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Label

    @ViewBuilder
    private func translationLabel(for block: TranslatedBlock) -> some View {
        let displayText: String = {
            if showingOriginal {
                block.originalText
            } else {
                block.translatedText.isEmpty ? block.originalText : block.translatedText
            }
        }()
        let size = block.fontSize

        Text(displayText.isEmpty ? "[空]" : displayText)
            .font(.system(size: size, weight: .regular, design: .default))
            .foregroundStyle(textColor(for: block))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .rotationEffect(block.isVertical ? .degrees(90) : .degrees(0))
    }

    // MARK: - Text color

    private func textColor(for block: TranslatedBlock) -> Color {
        let hasTextSample = block.textR > 0.01 || block.textG > 0.01 || block.textB > 0.01
        if hasTextSample {
            return Color(red: block.textR, green: block.textG, blue: block.textB)
        }
        return block.isLightBackground ? .black : .white
    }

    // MARK: - Background

    private func backgroundForBlock(_ block: TranslatedBlock) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: block.bgRed, green: block.bgGreen, blue: block.bgBlue))
    }

    // MARK: - Edge-aware width

    private func edgeAwareWidth(for block: TranslatedBlock) -> CGFloat {
        guard let edges = block.lineEdges else { return block.screenRect.width }
        let edgeWidth = edges.right - edges.left
        let screenW = NSScreen.main?.frame.width ?? 1920
        let captureW = block.captureRegion.width
        let scale = captureW > 0 ? screenW / captureW : 1
        return edgeWidth * captureW * scale / (NSScreen.main?.backingScaleFactor ?? 2)
    }

    private func alignmentForBlock(_ block: TranslatedBlock) -> Alignment {
        // Translations are anchored top-leading at the OCR box's start corner; the
        // frame width already reflects the actual ink extent (edgeAwareWidth).
        return .topLeading
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}

struct RegionMaskView: View {
    let selectedRegion: CGRect
    let dimOpacity: Double

    var body: some View {
        Canvas { context, size in
            let fullRect = CGRect(origin: .zero, size: size)
            context.fill(Path(fullRect), with: .color(.black.opacity(dimOpacity)))
            context.blendMode = .clear
            context.fill(Path(selectedRegion), with: .color(.black))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                .frame(width: selectedRegion.width, height: selectedRegion.height)
                .position(x: selectedRegion.midX, y: selectedRegion.midY)
                .allowsHitTesting(false)
        )
        .overlay(cornerIndicators)
    }

    private var cornerIndicators: some View {
        let cornerLen: CGFloat = 20
        let lineWidth: CGFloat = 2
        let color = Color.white.opacity(0.9)
        let r = selectedRegion

        return Canvas { context, _ in
            // Top-left corner
            var path = Path()
            path.move(to: CGPoint(x: r.minX, y: r.minY + cornerLen))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY))
            path.addLine(to: CGPoint(x: r.minX + cornerLen, y: r.minY))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Top-right corner
            path = Path()
            path.move(to: CGPoint(x: r.maxX - cornerLen, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + cornerLen))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Bottom-left corner
            path = Path()
            path.move(to: CGPoint(x: r.minX, y: r.maxY - cornerLen))
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX + cornerLen, y: r.maxY))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Bottom-right corner
            path = Path()
            path.move(to: CGPoint(x: r.maxX - cornerLen, y: r.maxY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cornerLen))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}
