import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OverlayRootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // 隐藏的 Apple 翻译 Provider — 始终挂载以提供 TranslationSession
            if #available(macOS 15, *) {
                AppleTranslationProvider(bridge: AppleTranslationBridge.shared)
            }

            switch appState.mode {
            case .idle:
                Color.clear

            case .regionSelecting:
                Color.black.opacity(0.25).ignoresSafeArea()
                RegionSelectionSurface(
                    borderColorHex: appState.selectionBorderColorHex,
                    borderStyle: appState.selectionBorderStyle,
                    borderLineWidth: appState.selectionBorderLineWidth,
                    onRegionSelected: { appState.handleRegionSelected($0) },
                    onCancel: { appState.exitToIdle() }
                )
                VStack {
                    Text("拖拽选择翻译区域")
                        .font(.title2).foregroundStyle(.white).shadow(radius: 4)
                    Text("按 Esc 取消")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }

            case .regionTranslating(let region):
                // Tap-anywhere-to-dismiss layer — sits below dim/labels, above
                // nothing. SwiftUI delivers gestures to the topmost child first,
                // so toolbar buttons (added later in this ZStack) win their hits.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { appState.exitToIdle() }

                TranslationOverlayView(
                    blocks: appState.translatedBlocks,
                    opacity: 0,
                    showingOriginal: appState.showingOriginal,
                    debugCapturedSize: appState.debugCapturedSize,
                    debugOCRCount: appState.debugOCRCount
                )
                SelectionCornerBorderView(
                    screenRegion: region,
                    colorHex: appState.selectionBorderColorHex,
                    style: appState.selectionBorderStyle,
                    lineWidth: appState.selectionBorderLineWidth
                )
                if appState.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                }
                if !appState.translatedBlocks.isEmpty && !appState.isProcessing {
                    TranslationToolbar(
                        showingOriginal: $appState.showingOriginal,
                        region: region,
                        onCopy: { appState.copyDisplayedText() },
                        onSaveImage: { appState.saveScreenshot(of: region) },
                        onDismiss: { appState.exitToIdle() },
                        toolbarOffset: $appState.regionToolbarOffset,
                        opacity: appState.regionToolbarOpacity
                    )
                }

            case .realtimeActive:
                Color.clear

            case .realtimeSelecting:
                Color.black.opacity(0.25).ignoresSafeArea()
                RegionSelectionSurface(
                    borderColorHex: appState.selectionBorderColorHex,
                    borderStyle: appState.selectionBorderStyle,
                    borderLineWidth: appState.selectionBorderLineWidth,
                    onRegionSelected: { appState.handleRealtimeRegionSelected($0) },
                    onCancel: { appState.mode = appState.realtimeRegions.isEmpty ? .idle : .realtimeActive }
                )
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RegionSelectionSurface: NSViewRepresentable {
    var borderColorHex: String
    var borderStyle: String
    var borderLineWidth: CGFloat
    let onRegionSelected: (CGRect) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RegionSelectorView {
        let view = RegionSelectorView()
        view.onRegionSelected = onRegionSelected
        view.onCancelled = onCancel
        applyAppearance(to: view)
        return view
    }

    func updateNSView(_ nsView: RegionSelectorView, context: Context) {
        applyAppearance(to: nsView)
    }

    private func applyAppearance(to view: RegionSelectorView) {
        view.borderColor = NSColor(hex: borderColorHex) ?? .black
        view.borderStyle = borderStyle
        view.borderLineWidth = borderLineWidth
    }
}

struct RealtimeRegionPanelView: View {
    @EnvironmentObject var appState: AppState
    let regionID: UUID

    var body: some View {
        if let region = appState.realtimeRegion(id: regionID) {
            let localRegion = OverlayCoordinateSpace.localRect(for: region.screenRegion)
            ZStack(alignment: .topLeading) {
                TranslationOverlayView(
                    blocks: region.translatedBlocks,
                    opacity: 0,
                    showingOriginal: region.showingOriginal,
                    coordinateOrigin: localRegion.origin
                )
                SelectionBorderView(
                    rect: CGRect(origin: .zero, size: region.screenRegion.size),
                    colorHex: appState.selectionBorderColorHex,
                    style: appState.selectionBorderStyle,
                    lineWidth: appState.selectionBorderLineWidth
                )
                if region.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .position(x: region.screenRegion.width / 2, y: region.screenRegion.height / 2)
                }
                RealtimeNumberBadge(
                    number: region.displayNumber,
                    colorHex: appState.realtimeBadgeColorHex,
                    textColorHex: appState.realtimeBadgeTextColorHex,
                    opacity: appState.realtimeBadgeOpacity,
                    fontSize: appState.realtimeBadgeFontSize
                )
                .position(x: 17, y: 17)
            }
            .frame(width: region.screenRegion.width, height: region.screenRegion.height)
            .clipped()
        } else {
            Color.clear
        }
    }
}

struct RealtimeToolbarPanelView: View {
    @EnvironmentObject var appState: AppState
    let regionID: UUID

    var body: some View {
        if let region = appState.realtimeRegion(id: regionID) {
            RealtimeToolbar(
                number: region.displayNumber,
                isProcessing: region.isProcessing,
                showingOriginal: Binding(
                    get: { appState.realtimeRegion(id: regionID)?.showingOriginal ?? false },
                    set: { appState.setRealtimeRegionShowingOriginal(id: regionID, showingOriginal: $0) }
                ),
                onCopy: { appState.copyRealtimeRegionText(id: regionID) },
                onSaveImage: { appState.saveRealtimeScreenshot(id: regionID) },
                onDismiss: { appState.closeRealtimeRegion(id: regionID) },
                onDragEnded: { appState.finishRealtimeToolbarDrag(id: regionID, frame: $0) },
                onSizeChange: { appState.updateRealtimeToolbarSize(id: regionID, size: $0) },
                opacity: appState.realtimeToolbarOpacity,
                badgeColorHex: appState.realtimeBadgeColorHex,
                badgeTextColorHex: appState.realtimeBadgeTextColorHex,
                badgeOpacity: appState.realtimeBadgeOpacity,
                badgeFontSize: appState.realtimeBadgeFontSize
            )
        } else {
            Color.clear
        }
    }
}

struct RealtimeNumberBadge: View {
    let number: Int
    let colorHex: String
    let textColorHex: String
    let opacity: Double
    let fontSize: CGFloat

    var body: some View {
        Text("\(number)")
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hex: textColorHex) ?? .white)
            .frame(minWidth: max(20, fontSize + 10), minHeight: max(20, fontSize + 10))
            .padding(.horizontal, 2)
            .background(
                Capsule()
                    .fill((Color(hex: colorHex) ?? .black).opacity(opacity))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            )
            .allowsHitTesting(false)
    }
}
