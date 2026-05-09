import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController {
    private let panel: OverlayPanel
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        self.panel = OverlayPanel()
        setupContentView()
    }

    private func setupContentView() {
        guard let appState else { return }
        let rootView = OverlayRootView().environmentObject(appState)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting
    }

    func showForSelection() {
        panel.orderFront(nil)
        panel.enableMouseEvents()
    }

    func showForTranslation(region: CGRect) {
        panel.orderFront(nil)
        // Keep mouse events enabled so toolbar buttons are clickable
    }

    func showFullScreenMask() {
        panel.orderFront(nil)
        panel.disableMouseEvents()
    }

    func showFullScreenForRegionSelection() {
        panel.orderFront(nil)
        panel.enableMouseEvents()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
