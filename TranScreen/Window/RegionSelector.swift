import AppKit

final class RegionSelectorView: NSView {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        isDragging = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        isDragging = true
        let current = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, currentRect.width > 10, currentRect.height > 10 else {
            onCancelled?()
            return
        }
        // 转换为屏幕坐标（AppKit: 左下角原点）
        let screenRect = window?.convertToScreen(currentRect) ?? currentRect
        onRegionSelected?(screenRect)
        startPoint = nil
        currentRect = .zero
        isDragging = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancelled?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isDragging, !currentRect.isEmpty else { return }

        // 选区边框
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let borderPath = NSBezierPath(rect: currentRect)
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        // 选区内部透明 cutout
        NSColor.clear.set()
        NSBezierPath(rect: currentRect).fill()
    }
}
