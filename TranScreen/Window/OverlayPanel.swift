import AppKit

final class OverlayPanel: NSPanel {

    init(screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    func enableMouseEvents() {
        ignoresMouseEvents = false
        makeKeyAndOrderFront(nil)
    }

    func disableMouseEvents() {
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
