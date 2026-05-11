import Foundation

struct OllamaEngine: TranslationEngine {
    let engineType = EngineType.ollama
    let configID: UUID
    let endpoint: String
    let modelID: String
    let temperature: Double
    let systemPrompt: String
    let customPrompt: String

    init(config: EngineConfig) throws {
        self.configID = config.id
        self.endpoint = config.endpointURL ?? "http://localhost:11434"
        self.modelID = config.modelID ?? "llama3"
        self.temperature = config.temperature
        self.systemPrompt = config.systemPrompt
        self.customPrompt = config.customPrompt
    }

    private func buildSystemPrompt(from sourceLang: String, to targetLang: String) -> String {
        var parts = [systemPrompt]
        parts.append("Translate from \(sourceLang) to \(targetLang). Return ONLY numbered translations.")
        if !customPrompt.isEmpty {
            parts.append(customPrompt)
        }
        return parts.joined(separator: "\n\n")
    }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String] {
        let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": buildSystemPrompt(from: sourceLang, to: targetLang)],
                ["role": "user", "content": numbered]
            ],
            "stream": false,
            "options": ["temperature": temperature]
        ]

        guard let url = URL(string: "\(endpoint)/api/chat") else { throw TranslationError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.invalidResponse(L10n.tr("error.ollamaResponseFormat"))
        }

        return parseNumberedResponse(content, expectedCount: texts.count)
    }

    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(endpoint)/api/tags") else { throw TranslationError.invalidEndpoint }
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.networkError(URLError(.badServerResponse))
        }
        return true
    }
}
