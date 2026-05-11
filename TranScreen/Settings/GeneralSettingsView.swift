import SwiftUI
import SwiftData
import AppKit

struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @State private var restartAlertLanguage = L10n.defaultLanguage
    @State private var showingRestartAlert = false

    private var settings: AppSettings {
        if let s = settingsList.first { return s }
        let s = AppSettings()
        modelContext.insert(s)
        return s
    }

    private let sourceLangs: [(String, String)] = [
        ("auto", "language.auto"), ("zh-Hans", "language.zhHans"), ("zh-Hant", "language.zhHant"),
        ("en", "language.en"), ("ja", "language.ja"), ("ko", "language.ko"),
        ("fr", "language.fr"), ("de", "language.de"), ("es", "language.es"), ("ru", "language.ru")
    ]
    private let targetLangs: [(String, String)] = [
        ("zh-Hans", "language.zhHans"), ("zh-Hant", "language.zhHant"), ("en", "language.en"),
        ("ja", "language.ja"), ("ko", "language.ko"), ("fr", "language.fr"), ("de", "language.de")
    ]

    var body: some View {
        Form {
            Section("语言") {
                Picker("显示语言", selection: displayLanguageBinding) {
                    ForEach(AppDisplayLanguage.allCases) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }
                Text("语言将在重启 TranScreen 后生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("源语言", selection: binding(\.sourceLang)) {
                    ForEach(sourceLangs, id: \.0) { Text(L10n.tr($0.1)).tag($0.0) }
                }
                Picker("目标语言", selection: binding(\.targetLang)) {
                    ForEach(targetLangs, id: \.0) { Text(L10n.tr($0.1)).tag($0.0) }
                }
            }

            Section("默认模式") {
                Picker("启动模式", selection: binding(\.defaultMode)) {
                    Text("截图选区").tag("region")
                    Text("实时翻译").tag("realtime")
                }
                .pickerStyle(.radioGroup)
            }

            Section("实时模式") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.format("settings.scanInterval", settings.scanInterval))
                    Slider(
                        value: binding(\.scanInterval),
                        in: 0.1...10.0,
                        step: 0.1
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(
            restartAlertText("restart.title"),
            isPresented: $showingRestartAlert
        ) {
            Button(restartAlertText("restart.confirm")) {
                relaunchApp()
            }
            Button(restartAlertText("restart.later"), role: .cancel) {}
        } message: {
            Text(restartAlertText("restart.message"))
        }
        .onAppear {
            settings.displayLanguage = AppDisplayLanguage.normalized(settings.displayLanguage)
            L10n.setPreferredLanguage(settings.displayLanguage)
            if settings.defaultMode == "fullscreen" {
                settings.defaultMode = "realtime"
                try? modelContext.save()
            }
            settings.scanInterval = max(0.1, min(10.0, settings.scanInterval))
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0; try? modelContext.save() }
        )
    }

    private var displayLanguageBinding: Binding<String> {
        Binding(
            get: { AppDisplayLanguage.normalized(settings.displayLanguage) },
            set: {
                let previousLanguage = AppDisplayLanguage.normalized(settings.displayLanguage)
                settings.displayLanguage = AppDisplayLanguage.normalized($0)
                L10n.setPreferredLanguage(settings.displayLanguage)
                try? modelContext.save()
                if settings.displayLanguage != previousLanguage {
                    restartAlertLanguage = settings.displayLanguage
                    showingRestartAlert = true
                }
            }
        )
    }

    private func restartAlertText(_ key: String) -> String {
        L10n.tr(key, language: restartAlertLanguage)
    }

    private func relaunchApp() {
        let escapedPath = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let command = "sleep 0.4; /usr/bin/open '\(escapedPath)'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }
}
