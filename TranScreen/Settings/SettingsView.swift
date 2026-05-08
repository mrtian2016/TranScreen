import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(0)

            EngineSettingsView()
                .tabItem { Label("翻译引擎", systemImage: "brain") }
                .tag(1)

            HotkeySettingsView()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
                .tag(2)

            AppearanceSettingsView()
                .tabItem { Label("外观", systemImage: "paintbrush") }
                .tag(3)
        }
        .frame(width: 560, height: 460)
    }
}
