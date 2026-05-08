import SwiftData
import Foundation
import CoreGraphics

@Model
final class HotkeyBinding {
    @Attribute(.unique) var actionRaw: String
    var keyCode: Int
    var modifiersRaw: UInt64
    var isEnabled: Bool

    var action: HotkeyAction? {
        HotkeyAction(rawValue: actionRaw)
    }

    var spec: HotkeySpec {
        get { HotkeySpec(keyCode: keyCode, modifiers: CGEventFlags(rawValue: modifiersRaw)) }
        set { keyCode = newValue.keyCode; modifiersRaw = newValue.modifiers.rawValue }
    }

    init(action: HotkeyAction, spec: HotkeySpec? = nil, isEnabled: Bool = true) {
        self.actionRaw = action.rawValue
        let s = spec ?? action.defaultBinding
        self.keyCode = s.keyCode
        self.modifiersRaw = s.modifiers.rawValue
        self.isEnabled = isEnabled
    }
}
