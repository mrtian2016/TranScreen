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
    var selectionBorderColorHex: String = "#000000"
    var selectionBorderStyle: String = "corners"
    var selectionBorderLineWidth: Double = 1.4
    var regionToolbarOpacity: Double = 0.9
    var realtimeToolbarOpacity: Double = 0.5
    var realtimeBadgeColorHex: String = "#111111"
    var realtimeBadgeTextColorHex: String = "#FFFFFF"
    var realtimeBadgeOpacity: Double = 0.8
    var realtimeBadgeFontSize: Double = 11.0
    var displayLanguage: String = L10n.defaultLanguage

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
        self.selectionBorderColorHex = "#000000"
        self.selectionBorderStyle = "corners"
        self.selectionBorderLineWidth = 1.4
        self.regionToolbarOpacity = 0.9
        self.realtimeToolbarOpacity = 0.5
        self.realtimeBadgeColorHex = "#111111"
        self.realtimeBadgeTextColorHex = "#FFFFFF"
        self.realtimeBadgeOpacity = 0.8
        self.realtimeBadgeFontSize = 11.0
        self.displayLanguage = L10n.defaultLanguage
    }
}
