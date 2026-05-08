import SwiftUI

struct TranslationOverlayView: View {
    let blocks: [TranslatedBlock]
    let opacity: Double
    var textColor: Color = .white
    var debugCapturedSize: CGSize = .zero
    var debugOCRCount: Int = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(opacity)
                    .ignoresSafeArea()

                // 调试角标
                VStack(alignment: .leading, spacing: 2) {
                    Text("blocks: \(blocks.count)  ocrRaw: \(debugOCRCount)")
                    Text("captured: \(Int(debugCapturedSize.width))×\(Int(debugCapturedSize.height))px")
                    if let first = blocks.first {
                        Text("rect[0]: \(Int(first.screenRect.minX)),\(Int(first.screenRect.minY)) \(Int(first.screenRect.width))×\(Int(first.screenRect.height))")
                        let displayText = first.translatedText.isEmpty ? first.originalText : first.translatedText
                        Text("text[0]: \(String(displayText.prefix(40)))")
                    }
                    Text("geo: \(Int(geo.size.width))×\(Int(geo.size.height))")
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.yellow)
                .padding(8)
                .background(Color.black.opacity(0.85))
                .cornerRadius(6)
                .position(x: 180, y: 60)

                ForEach(blocks) { block in
                    translationLabel(for: block)
                        .position(
                            x: clamp(block.screenRect.midX, min: 0, max: geo.size.width),
                            y: clamp(block.screenRect.midY, min: 0, max: geo.size.height)
                        )
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func translationLabel(for block: TranslatedBlock) -> some View {
        let displayText = block.translatedText.isEmpty ? block.originalText : block.translatedText
        let size = max(14, block.fontSize)

        Text(displayText.isEmpty ? "[空]" : displayText)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
            )
            .fixedSize()  // 让文本按内容自然展开，不强制宽高
            .rotationEffect(block.isVertical ? .degrees(90) : .degrees(0))
    }

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
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                .frame(width: selectedRegion.width, height: selectedRegion.height)
                .position(x: selectedRegion.midX, y: selectedRegion.midY)
        )
    }
}
