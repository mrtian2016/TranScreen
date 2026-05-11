import SwiftUI
import SwiftData

struct HotkeySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bindings: [HotkeyBinding]
    @EnvironmentObject private var appState: AppState

    @State private var recordingAction: HotkeyAction?
    @State private var conflictWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !AXIsProcessTrusted() {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("需要辅助功能权限才能使用全局快捷键").font(.callout)
                    Spacer()
                    Button("前往授权") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding()
            }

            if let warning = conflictWarning {
                Text("⚠️ \(warning)").font(.caption).foregroundStyle(.orange).padding(.horizontal)
            }

            List {
                ForEach(HotkeyAction.allCases) { action in
                    HotkeyRow(
                        action: action,
                        binding: bindingFor(action),
                        isRecording: recordingAction == action
                    ) {
                        appState.pauseHotkeyMonitoringForRecording()
                        recordingAction = action
                    } onSpecChanged: { newSpec in
                        updateBinding(action: action, spec: newSpec)
                        recordingAction = nil
                        appState.startHotkeyMonitoring(with: bindings)
                    } onCancelRecording: {
                        recordingAction = nil
                        appState.startHotkeyMonitoring(with: bindings)
                    } onReset: {
                        updateBinding(action: action, spec: action.defaultBinding)
                        recordingAction = nil
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Button("恢复所有默认") {
                    for action in HotkeyAction.allCases {
                        updateBinding(action: action, spec: action.defaultBinding)
                    }
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("点击快捷键区域开始录制，Esc 取消").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .onAppear { ensureDefaultBindings() }
        .onDisappear {
            recordingAction = nil
            appState.startHotkeyMonitoring(with: bindings)
        }
    }

    private func bindingFor(_ action: HotkeyAction) -> HotkeyBinding {
        bindings.first { $0.actionRaw == action.rawValue } ?? HotkeyBinding(action: action)
    }

    private func updateBinding(action: HotkeyAction, spec: HotkeySpec) {
        // 冲突检测
        for other in HotkeyAction.allCases where other != action {
            if bindingFor(other).spec == spec {
                conflictWarning = L10n.format("hotkey.conflict", other.displayName)
                return
            }
        }
        conflictWarning = nil

        if let existing = bindings.first(where: { $0.actionRaw == action.rawValue }) {
            existing.spec = spec
        } else {
            modelContext.insert(HotkeyBinding(action: action, spec: spec))
        }
        try? modelContext.save()
        appState.startHotkeyMonitoring(with: bindings)
    }

    private func ensureDefaultBindings() {
        var changed = false
        for action in HotkeyAction.allCases {
            if let existing = bindings.first(where: { $0.actionRaw == action.rawValue }) {
                if !existing.spec.isValid {
                    existing.spec = action.defaultBinding
                    changed = true
                }
            } else {
                modelContext.insert(HotkeyBinding(action: action))
                changed = true
            }
        }
        if changed {
            try? modelContext.save()
            appState.startHotkeyMonitoring(with: bindings)
        }
    }
}

struct HotkeyRow: View {
    let action: HotkeyAction
    let binding: HotkeyBinding
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onSpecChanged: (HotkeySpec) -> Void
    let onCancelRecording: () -> Void
    let onReset: () -> Void

    @State private var localSpec: HotkeySpec = HotkeySpec(keyCode: -1, modifiers: [])
    @State private var localIsRecording = false

    var body: some View {
        HStack {
            Text(action.displayName).frame(width: 160, alignment: .leading)
            Spacer()

            Button(action: onStartRecording) {
                HotkeyRecorder(
                    spec: $localSpec,
                    isRecording: $localIsRecording,
                    onCancelled: onCancelRecording
                )
                    .frame(width: 120, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.format("hotkey.resetDefaultHelp", action.defaultBinding.displayString))

            Toggle("", isOn: Binding(
                get: { binding.isEnabled },
                set: { binding.isEnabled = $0 }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .onAppear {
            localSpec = binding.spec
            localIsRecording = isRecording
        }
        .onChange(of: isRecording) { _, v in localIsRecording = v }
        .onChange(of: localSpec) { _, newSpec in
            if newSpec.isValid { onSpecChanged(newSpec) }
        }
    }
}
