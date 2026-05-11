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

    @State private var borderColor: Color = .black
    @State private var badgeColor: Color = .black
    @State private var badgeTextColor: Color = .white

    var body: some View {
        Form {
            Section("选区边框") {
                ColorPicker("边框颜色", selection: $borderColor)
                    .onChange(of: borderColor) { _, color in
                        if let hex = color.toHex() {
                            settings.selectionBorderColorHex = hex
                            appState.objectWillChange.send()
                            try? modelContext.save()
                        }
                    }

                Picker("边框样式", selection: Binding(
                    get: { settings.selectionBorderStyle },
                    set: {
                        settings.selectionBorderStyle = $0
                        appState.objectWillChange.send()
                        try? modelContext.save()
                    }
                )) {
                    Text("四角").tag("corners")
                    Text("完整边框").tag("full")
                    Text("虚线边框").tag("dashed")
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading) {
                    Text(L10n.format("appearance.lineWidth", settings.selectionBorderLineWidth))
                    Slider(
                        value: Binding(
                            get: { settings.selectionBorderLineWidth },
                            set: { v in
                                settings.selectionBorderLineWidth = v
                                appState.objectWillChange.send()
                                try? modelContext.save()
                            }
                        ),
                        in: 0.5...5.0, step: 0.1
                    )
                }
            }

            Section("工具条透明度") {
                VStack(alignment: .leading) {
                    Text(L10n.format("appearance.regionToolbarOpacity", Int(settings.regionToolbarOpacity * 100)))
                    Slider(
                        value: Binding(
                            get: { settings.regionToolbarOpacity },
                            set: {
                                settings.regionToolbarOpacity = $0
                                appState.objectWillChange.send()
                                try? modelContext.save()
                            }
                        ),
                        in: 0.2...1.0,
                        step: 0.05
                    )
                }

                VStack(alignment: .leading) {
                    Text(L10n.format("appearance.realtimeToolbarOpacity", Int(settings.realtimeToolbarOpacity * 100)))
                    Slider(
                        value: Binding(
                            get: { settings.realtimeToolbarOpacity },
                            set: {
                                settings.realtimeToolbarOpacity = $0
                                appState.objectWillChange.send()
                                try? modelContext.save()
                            }
                        ),
                        in: 0.2...1.0,
                        step: 0.05
                    )
                }
            }

            Section("实时编号") {
                ColorPicker("编号颜色", selection: $badgeColor)
                    .onChange(of: badgeColor) { _, color in
                        if let hex = color.toHex() {
                            settings.realtimeBadgeColorHex = hex
                            appState.objectWillChange.send()
                            try? modelContext.save()
                        }
                    }

                ColorPicker("文字颜色", selection: $badgeTextColor)
                    .onChange(of: badgeTextColor) { _, color in
                        if let hex = color.toHex() {
                            settings.realtimeBadgeTextColorHex = hex
                            appState.objectWillChange.send()
                            try? modelContext.save()
                        }
                    }

                VStack(alignment: .leading) {
                    Text(L10n.format("appearance.badgeBackgroundOpacity", Int(settings.realtimeBadgeOpacity * 100)))
                    Slider(
                        value: Binding(
                            get: { settings.realtimeBadgeOpacity },
                            set: {
                                settings.realtimeBadgeOpacity = $0
                                appState.objectWillChange.send()
                                try? modelContext.save()
                            }
                        ),
                        in: 0.2...1.0,
                        step: 0.05
                    )
                }

                VStack(alignment: .leading) {
                    Text(L10n.format("appearance.badgeFontSize", settings.realtimeBadgeFontSize))
                    Slider(
                        value: Binding(
                            get: { settings.realtimeBadgeFontSize },
                            set: {
                                settings.realtimeBadgeFontSize = $0
                                appState.objectWillChange.send()
                                try? modelContext.save()
                            }
                        ),
                        in: 9...18,
                        step: 1
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            borderColor = Color(hex: settings.selectionBorderColorHex) ?? .black
            badgeColor = Color(hex: settings.realtimeBadgeColorHex) ?? .black
            badgeTextColor = Color(hex: settings.realtimeBadgeTextColorHex) ?? .white
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
        guard let int = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let int = UInt64(hex, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat(Double((int >> 16) & 0xFF) / 255.0),
            green: CGFloat(Double((int >> 8) & 0xFF) / 255.0),
            blue: CGFloat(Double(int & 0xFF) / 255.0),
            alpha: 1
        )
    }
}
