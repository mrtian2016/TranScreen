import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text(statusText)
            .foregroundStyle(.secondary)

        Divider()

        Button("选区翻译") { appState.enterRegionSelect() }
        Button(appState.mode == .fullScreenMask ? "退出全屏蒙版" : "全屏蒙版翻译") {
            appState.toggleFullScreenMask()
        }

        if !appState.hasScreenRecordingPermission || !appState.hasAccessibilityPermission {
            Divider()
            Button("授予必要权限") { appState.requestPermissions() }
        }

        if let error = appState.lastError {
            Divider()
            Text("⚠️ \(error)")
                .foregroundStyle(.red)
        }

        Divider()

        SettingsLink { Text("偏好设置...") }
        Button("退出 TranScreen") { NSApplication.shared.terminate(nil) }
    }

    private var statusText: String {
        switch appState.mode {
        case .idle: return "● 空闲"
        case .regionSelecting: return "● 选择区域中"
        case .regionTranslating: return appState.isProcessing ? "● 翻译中..." : "● 显示译文"
        case .fullScreenMask: return "● 全屏蒙版"
        case .fullScreenRegionSelecting: return "● 全屏选区中"
        }
    }
}
