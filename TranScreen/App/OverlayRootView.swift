import SwiftUI
import AppKit

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
                    onRegionSelected: { appState.handleRegionSelected($0) },
                    onCancel: { appState.exitToIdle() }
                )
                VStack {
                    Text("拖拽选择翻译区域")
                        .font(.title2).foregroundStyle(.white).shadow(radius: 4)
                    Text("按 Esc 取消")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }

            case .regionTranslating:
                TranslationOverlayView(
                    blocks: appState.translatedBlocks,
                    opacity: appState.overlayOpacity,
                    debugCapturedSize: appState.debugCapturedSize,
                    debugOCRCount: appState.debugOCRCount
                )
                if appState.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                }

            case .fullScreenMask:
                TranslationOverlayView(
                    blocks: appState.translatedBlocks,
                    opacity: appState.overlayOpacity,
                    debugCapturedSize: appState.debugCapturedSize,
                    debugOCRCount: appState.debugOCRCount
                )
                if appState.isProcessing {
                    VStack {
                        Spacer()
                        HStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                            Text("扫描中...").font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                    }
                }

            case .fullScreenRegionSelecting:
                Color.black.opacity(appState.overlayOpacity).ignoresSafeArea()
                RegionSelectionSurface(
                    onRegionSelected: { appState.handleRegionSelected($0) },
                    onCancel: { appState.mode = .fullScreenMask }
                )
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RegionSelectionSurface: NSViewRepresentable {
    let onRegionSelected: (CGRect) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RegionSelectorView {
        let view = RegionSelectorView()
        view.onRegionSelected = onRegionSelected
        view.onCancelled = onCancel
        return view
    }

    func updateNSView(_ nsView: RegionSelectorView, context: Context) {}
}
