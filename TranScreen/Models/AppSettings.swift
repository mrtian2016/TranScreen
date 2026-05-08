import SwiftData
import Foundation

@Model
final class AppSettings {
    var sourceLang: String
    var targetLang: String
    var defaultMode: String
    var scanInterval: Double
    var powerSavingEnabled: Bool
    var overlayOpacity: Double
    var textColorHex: String
    var fontSizeMode: String
    var fixedFontSize: Double

    init() {
        self.sourceLang = "auto"
        self.targetLang = "zh-Hans"
        self.defaultMode = "region"
        self.scanInterval = 2.0
        self.powerSavingEnabled = false
        self.overlayOpacity = 0.5
        self.textColorHex = "#FFFFFF"
        self.fontSizeMode = "adaptive"
        self.fixedFontSize = 14.0
    }
}
