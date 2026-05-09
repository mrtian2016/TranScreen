import SwiftData
import Foundation

enum EngineType: String, Codable, CaseIterable, Identifiable {
    case apple = "apple"
    case openAICompatible = "openai_compatible"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case deepL = "deepl"
    case ollama = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple 翻译（离线）"
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropic: return "Anthropic Claude"
        case .gemini: return "Google Gemini"
        case .deepL: return "DeepL"
        case .ollama: return "Ollama（本地）"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .apple, .ollama: return false
        default: return true
        }
    }

    var requiresEndpoint: Bool {
        switch self {
        case .openAICompatible, .ollama: return true
        default: return false
        }
    }

    var requiresModelID: Bool {
        switch self {
        case .openAICompatible, .anthropic, .gemini, .ollama: return true
        default: return false
        }
    }

    var supportsTemperature: Bool {
        switch self {
        case .openAICompatible, .anthropic, .gemini, .ollama: return true
        default: return false
        }
    }

    var supportsCustomPrompt: Bool {
        supportsTemperature
    }
}

@Model
final class EngineConfig {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var engineTypeRaw: String
    var endpointURL: String?
    var modelID: String?
    var isEnabled: Bool
    var sortOrder: Int
    var createdAt: Date
    var temperature: Double = 0.3
    var systemPrompt: String = "你是一个有用的翻译助手"
    var customPrompt: String = ""

    var engineType: EngineType {
        get { EngineType(rawValue: engineTypeRaw) ?? .openAICompatible }
        set { engineTypeRaw = newValue.rawValue }
    }

    init(
        displayName: String,
        engineType: EngineType,
        endpointURL: String? = nil,
        modelID: String? = nil,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        temperature: Double = 0.3,
        systemPrompt: String = "你是一个有用的翻译助手",
        customPrompt: String = ""
    ) {
        self.id = UUID()
        self.displayName = displayName
        self.engineTypeRaw = engineType.rawValue
        self.endpointURL = endpointURL
        self.modelID = modelID
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.temperature = temperature
        self.systemPrompt = systemPrompt
        self.customPrompt = customPrompt
    }
}
