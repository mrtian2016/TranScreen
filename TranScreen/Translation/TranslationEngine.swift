import Foundation

enum TranslationError: Error, LocalizedError {
    case noAPIKey
    case invalidEndpoint
    case networkError(Error)
    case rateLimited
    case invalidResponse(String)
    case missingModelID
    case allEnginesFailed
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return L10n.tr("error.noAPIKey")
        case .invalidEndpoint: return L10n.tr("error.invalidEndpoint")
        case .networkError(let e): return L10n.format("error.network", e.localizedDescription)
        case .rateLimited: return L10n.tr("error.rateLimited")
        case .invalidResponse(let s): return L10n.format("error.invalidResponse", s)
        case .missingModelID: return L10n.tr("error.missingModelID")
        case .allEnginesFailed: return L10n.tr("error.allEnginesFailed")
        case .notAvailable: return L10n.tr("error.engineNotAvailable")
        }
    }
}

protocol TranslationEngine: Sendable {
    var engineType: EngineType { get }
    var configID: UUID { get }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String]
    func testConnection() async throws -> Bool
}

// 数字编号响应解析（所有 LLM 引擎共用）
func parseNumberedResponse(_ text: String, expectedCount: Int) -> [String] {
    var results = text.components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { line -> String in
            // 移除 "1. " / "1) " / "1、" 格式前缀
            let pattern = #"^\d+[.)、]\s*"#
            return line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        .filter { !$0.isEmpty }
    while results.count < expectedCount { results.append("") }
    return Array(results.prefix(expectedCount))
}
