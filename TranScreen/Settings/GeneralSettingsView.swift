import SwiftUI
import SwiftData

struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings {
        if let s = settingsList.first { return s }
        let s = AppSettings()
        modelContext.insert(s)
        return s
    }

    private let sourceLangs: [(String, String)] = [
        ("auto", "自动检测"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁体中文"),
        ("en", "英语"), ("ja", "日语"), ("ko", "韩语"),
        ("fr", "法语"), ("de", "德语"), ("es", "西班牙语"), ("ru", "俄语")
    ]
    private let targetLangs: [(String, String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁体中文"), ("en", "英语"),
        ("ja", "日语"), ("ko", "韩语"), ("fr", "法语"), ("de", "德语")
    ]

    var body: some View {
        Form {
            Section("语言") {
                Picker("源语言", selection: binding(\.sourceLang)) {
                    ForEach(sourceLangs, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("目标语言", selection: binding(\.targetLang)) {
                    ForEach(targetLangs, id: \.0) { Text($0.1).tag($0.0) }
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
                    Text("扫描间隔: \(settings.scanInterval, specifier: "%.1f") 秒")
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
        .onAppear {
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
}
