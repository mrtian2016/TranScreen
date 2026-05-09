import Foundation

struct AnthropicEngine: TranslationEngine {
    let engineType = EngineType.anthropic
    let configID: UUID
    let modelID: String
    let temperature: Double
    let systemPrompt: String
    let customPrompt: String

    private static let endpoint = "https://api.anthropic.com/v1/messages"
    private static let apiVersion = "2023-06-01"

    init(config: EngineConfig) throws {
        self.configID = config.id
        self.modelID = config.modelID ?? "claude-haiku-4-5-20251001"
        self.temperature = config.temperature
        self.systemPrompt = config.systemPrompt
        self.customPrompt = config.customPrompt
    }

    private func loadAPIKey() throws -> String {
        guard let key = try? KeychainHelper.load(key: configID.uuidString), !key.isEmpty else {
            throw TranslationError.noAPIKey
        }
        return key
    }

    private func buildSystemPrompt(from sourceLang: String, to targetLang: String) -> String {
        var parts = [systemPrompt]
        parts.append("You are a professional translator. Translate the following numbered texts from \(sourceLang) to \(targetLang). Return ONLY the translated texts in the same numbered format.")
        if !customPrompt.isEmpty {
            parts.append(customPrompt)
        }
        return parts.joined(separator: "\n\n")
    }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String] {
        let apiKey = try loadAPIKey()
        let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 2048,
            "temperature": temperature,
            "system": buildSystemPrompt(from: sourceLang, to: targetLang),
            "messages": [["role": "user", "content": numbered]]
        ]

        guard let url = URL(string: Self.endpoint) else { throw TranslationError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.networkError(URLError(.badServerResponse))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw TranslationError.invalidResponse("Anthropic 响应格式错误")
        }

        return parseNumberedResponse(text, expectedCount: texts.count)
    }

    func testConnection() async throws -> Bool {
        _ = try await translate(texts: ["Hello"], from: "en", to: "zh-Hans")
        return true
    }
}
