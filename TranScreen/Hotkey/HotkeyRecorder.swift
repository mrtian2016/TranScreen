import SwiftUI
import AppKit
import Carbon

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var spec: HotkeySpec
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onSpecRecorded = { newSpec in
            spec = newSpec
            isRecording = false
        }
        view.onCancelled = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.isRecording = isRecording
        nsView.currentSpec = spec
        nsView.needsDisplay = true
    }
}

final class HotkeyRecorderView: NSView {
    var isRecording = false {
        didSet {
            needsDisplay = true
            if isRecording { window?.makeFirstResponder(self) }
        }
    }
    var currentSpec = HotkeySpec(keyCode: -1, modifiers: [])
    var onSpecRecorded: ((HotkeySpec) -> Void)?
    var onCancelled: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let text = isRecording ? "按下快捷键..." : currentSpec.displayString
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.systemBlue : NSColor.labelColor
        ]

        let bg = isRecording ? NSColor.systemBlue.withAlphaComponent(0.1) : NSColor.controlBackgroundColor
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        let border = isRecording ? NSColor.systemBlue : NSColor.separatorColor
        border.setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        borderPath.lineWidth = 1
        borderPath.stroke()

        let textSize = (text as NSString).size(withAttributes: attr)
        let textRect = CGRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attr)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        let keyCode = Int(event.keyCode)
        let modifierKeyCodes = [kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
                                kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl]
        if modifierKeyCodes.contains(keyCode) { return }

        // Esc 无修饰键 = 取消录制
        if keyCode == kVK_Escape && !event.modifierFlags.contains(.command) &&
            !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.option) &&
            !event.modifierFlags.contains(.control) {
            onCancelled?()
            return
        }

        let flags = event.modifierFlags.cgEventFlags.intersection(
            [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        )
        onSpecRecorded?(HotkeySpec(keyCode: keyCode, modifiers: flags))
    }
}

extension NSEvent.ModifierFlags {
    var cgEventFlags: CGEventFlags {
        var flags = CGEventFlags()
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        return flags
    }
}
