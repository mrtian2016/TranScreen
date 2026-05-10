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

@MainActor
final class RealtimeRegionPanelController {
    private let contentPanel: NSPanel
    private let toolbarPanel: NSPanel
    private let screenRegion: CGRect
    private var toolbarSize = CGSize(width: 320, height: 36)

    init(appState: AppState, regionID: UUID, screenRegion: CGRect) {
        self.screenRegion = screenRegion
        self.contentPanel = NSPanel(
            contentRect: screenRegion,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.toolbarPanel = NSPanel(
            contentRect: Self.toolbarFrame(for: screenRegion, toolbarSize: toolbarSize, offset: .zero),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(panel: contentPanel, ignoresMouseEvents: true)
        configure(panel: toolbarPanel, ignoresMouseEvents: false, isToolbar: true)

        let rootView = RealtimeRegionPanelView(regionID: regionID)
            .environmentObject(appState)
            .frame(width: screenRegion.width, height: screenRegion.height)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = CGRect(origin: .zero, size: screenRegion.size)
        contentPanel.contentView = hosting

        let toolbarView = RealtimeToolbarPanelView(regionID: regionID)
            .environmentObject(appState)
        let toolbarHosting = NSHostingView(rootView: toolbarView)
        toolbarHosting.frame = CGRect(origin: .zero, size: toolbarSize)
        toolbarPanel.contentView = toolbarHosting
    }

    private func configure(panel: NSPanel, ignoresMouseEvents: Bool, isToolbar: Bool = false) {
        panel.level = isToolbar
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            : .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = ignoresMouseEvents
        panel.animationBehavior = .none
    }

    func show() {
        contentPanel.orderFront(nil)
        toolbarPanel.orderFront(nil)
    }

    func close() {
        contentPanel.orderOut(nil)
        toolbarPanel.orderOut(nil)
    }

    @discardableResult
    func updateToolbarSize(_ size: CGSize) -> Bool {
        let sanitized = CGSize(
            width: max(160, ceil(size.width)),
            height: max(32, ceil(size.height))
        )
        guard abs(sanitized.width - toolbarSize.width) > 0.5 ||
                abs(sanitized.height - toolbarSize.height) > 0.5 else { return false }
        toolbarSize = sanitized
        let oldFrame = toolbarPanel.frame
        toolbarPanel.setFrame(
            CGRect(origin: oldFrame.origin, size: toolbarSize),
            display: true
        )
        return true
    }

    func setToolbarFrame(_ frame: CGRect) {
        toolbarPanel.setFrame(frame, display: true)
        toolbarPanel.orderFront(nil)
    }

    func toolbarFrame(forOffset offset: CGSize) -> CGRect {
        Self.toolbarFrame(for: screenRegion, toolbarSize: toolbarSize, offset: offset)
    }

    func offset(forToolbarOrigin origin: CGPoint) -> CGSize {
        let base = Self.toolbarFrame(for: screenRegion, toolbarSize: toolbarSize, offset: .zero)
        return CGSize(
            width: origin.x - base.origin.x,
            height: base.origin.y - origin.y
        )
    }

    var toolbarFrame: CGRect {
        toolbarPanel.frame
    }

    var windowIDs: [CGWindowID] {
        [contentPanel.windowNumber, toolbarPanel.windowNumber].map { CGWindowID($0) }
    }

    private static func toolbarFrame(for region: CGRect, toolbarSize: CGSize, offset: CGSize) -> CGRect {
        let gap: CGFloat = 4
        return CGRect(
            x: region.maxX - toolbarSize.width - gap + offset.width,
            y: region.minY + gap - offset.height,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
    }
}
