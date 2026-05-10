import Foundation
import Carbon
import CoreGraphics

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case triggerRegionSelect = "triggerRegionSelect"
    case toggleFullScreenMask = "toggleFullScreenMask"
    case fullScreenRegionSelect = "fullScreenRegionSelect"
    case exitToIdle = "exitToIdle"
    case increaseOpacity = "increaseOpacity"
    case decreaseOpacity = "decreaseOpacity"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .triggerRegionSelect: return "选区截图翻译"
        case .toggleFullScreenMask: return "实时翻译"
        case .fullScreenRegionSelect: return "实时模式选区"
        case .exitToIdle: return "退出/取消"
        case .increaseOpacity: return "增加工具条不透明度"
        case .decreaseOpacity: return "降低工具条不透明度"
        }
    }

    var defaultKeyCode: Int {
        switch self {
        case .triggerRegionSelect: return kVK_ANSI_E
        case .toggleFullScreenMask: return kVK_ANSI_M
        case .fullScreenRegionSelect: return kVK_ANSI_E
        case .exitToIdle: return kVK_Escape
        case .increaseOpacity: return kVK_ANSI_Equal
        case .decreaseOpacity: return kVK_ANSI_Minus
        }
    }

    var defaultModifiers: CGEventFlags {
        switch self {
        case .triggerRegionSelect: return .maskCommand
        case .toggleFullScreenMask: return .maskCommand
        case .fullScreenRegionSelect: return [.maskCommand, .maskShift]
        case .exitToIdle: return []
        case .increaseOpacity: return .maskCommand
        case .decreaseOpacity: return .maskCommand
        }
    }

    var defaultBinding: HotkeySpec {
        HotkeySpec(keyCode: defaultKeyCode, modifiers: defaultModifiers)
    }
}

struct HotkeySpec: Codable, Equatable, Hashable {
    var keyCode: Int
    var modifiers: CGEventFlags

    var isValid: Bool { keyCode >= 0 }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    static func == (lhs: HotkeySpec, rhs: HotkeySpec) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("⌃") }
        if modifiers.contains(.maskAlternate) { parts.append("⌥") }
        if modifiers.contains(.maskShift) { parts.append("⇧") }
        if modifiers.contains(.maskCommand) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: Int) -> String {
        switch code {
        case kVK_Escape: return "Esc"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        default: return "(\(code))"
        }
    }

}

extension CGEventFlags: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(UInt64.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
