import SwiftUI
import SwiftData
import AppKit

struct AppearanceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @EnvironmentObject private var appState: AppState

    private var settings: AppSettings {
        if let s = settingsList.first { return s }
        let s = AppSettings()
        modelContext.insert(s)
        return s
    }

    @State private var textColor: Color = .white

    var body: some View {
        Form {
            Section("蒙版") {
                VStack(alignment: .leading) {
                    Text("蒙版暗度: \(Int(settings.overlayOpacity * 100))%")
                    Slider(
                        value: Binding(
                            get: { settings.overlayOpacity },
                            set: { v in
                                settings.overlayOpacity = v
                                appState.overlayOpacity = v
                                try? modelContext.save()
                            }
                        ),
                        in: 0.1...0.9, step: 0.05
                    )
                }
            }

            Section("译文文字") {
                ColorPicker("文字颜色", selection: $textColor)
                    .onChange(of: textColor) { _, color in
                        if let hex = color.toHex() {
                            settings.textColorHex = hex
                            try? modelContext.save()
                        }
                    }

                Picker("字号模式", selection: Binding(
                    get: { settings.fontSizeMode },
                    set: { settings.fontSizeMode = $0; try? modelContext.save() }
                )) {
                    Text("自适应（推荐）").tag("adaptive")
                    Text("固定大小").tag("fixed")
                }
                .pickerStyle(.radioGroup)

                if settings.fontSizeMode == "fixed" {
                    HStack {
                        Text("固定字号: \(Int(settings.fixedFontSize))pt")
                        Slider(
                            value: Binding(
                                get: { settings.fixedFontSize },
                                set: { settings.fixedFontSize = $0; try? modelContext.save() }
                            ),
                            in: 9...36, step: 1
                        )
                    }
                }
            }

            Section("预览") {
                ZStack {
                    Color.gray.opacity(0.3)
                    Text("译文预览文字")
                        .font(.system(size: settings.fontSizeMode == "fixed" ? settings.fixedFontSize : 16))
                        .foregroundStyle(textColor)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                }
                .frame(height: 60)
                .cornerRadius(8)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            textColor = Color(hex: settings.textColorHex) ?? .white
        }
    }
}

extension Color {
    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        self.init(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}
