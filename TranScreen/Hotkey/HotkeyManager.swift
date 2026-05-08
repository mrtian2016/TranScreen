import AppKit
import Carbon

@MainActor
final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bindings: [HotkeySpec: HotkeyAction] = [:]

    weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func loadBindings(_ hotkeyBindings: [HotkeyBinding]) {
        var newMap: [HotkeySpec: HotkeyAction] = [:]
        for binding in hotkeyBindings where binding.isEnabled {
            if let action = binding.action {
                newMap[binding.spec] = action
            }
        }

        if newMap.isEmpty {
            for action in HotkeyAction.allCases {
                newMap[action.defaultBinding] = action
            }
        }

        self.bindings = newMap
        unregister()
        register()
    }

    func register() {
        guard AXIsProcessTrusted() else {
            print("⚠️ 缺少辅助功能权限，无法注册全局快捷键")
            return
        }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            print("⚠️ CGEvent.tapCreate 失败")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("✅ 全局快捷键注册成功，已绑定 \(bindings.count) 个动作")
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        let spec = HotkeySpec(keyCode: keyCode, modifiers: flags)

        guard let action = bindings[spec] else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.executeAction(action)
        }

        return nil
    }

    @MainActor
    private func executeAction(_ action: HotkeyAction) {
        guard let appState else { return }
        switch action {
        case .triggerRegionSelect:
            appState.enterRegionSelect()
        case .toggleFullScreenMask:
            appState.toggleFullScreenMask()
        case .fullScreenRegionSelect:
            if appState.mode == .fullScreenMask {
                appState.mode = .fullScreenRegionSelecting
            }
        case .exitToIdle:
            appState.exitToIdle()
        case .increaseOpacity:
            appState.adjustOpacity(by: 0.1)
        case .decreaseOpacity:
            appState.adjustOpacity(by: -0.1)
        }
    }
}
