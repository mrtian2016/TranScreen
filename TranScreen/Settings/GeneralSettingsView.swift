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
                    Text("全屏蒙版").tag("fullscreen")
                }
                .pickerStyle(.radioGroup)
            }

            Section("全屏扫描") {
                Picker("扫描间隔", selection: binding(\.scanInterval)) {
                    Text("1 秒（高频）").tag(1.0)
                    Text("2 秒（推荐）").tag(2.0)
                    Text("5 秒（省电）").tag(5.0)
                }
                Toggle("省电模式（固定 5 秒间隔）", isOn: binding(\.powerSavingEnabled))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0; try? modelContext.save() }
        )
    }
}
