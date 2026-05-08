import Foundation

struct GeminiEngine: TranslationEngine {
    let engineType = EngineType.gemini
    let configID: UUID
    let modelID: String

    init(config: EngineConfig) throws {
        self.configID = config.id
        self.modelID = config.modelID ?? "gemini-1.5-flash"
        // API Key 改为按需加载
    }

    private func loadAPIKey() throws -> String {
        guard let key = try? KeychainHelper.load(key: configID.uuidString), !key.isEmpty else {
            throw TranslationError.noAPIKey
        }
        return key
    }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String] {
        let apiKey = try loadAPIKey()
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw TranslationError.invalidEndpoint }

        let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let prompt = "Translate from \(sourceLang) to \(targetLang). Return ONLY numbered translations:\n\(numbered)"

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.1, "maxOutputTokens": 2048]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.networkError(URLError(.badServerResponse))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw TranslationError.invalidResponse("Gemini 响应格式错误")
        }

        return parseNumberedResponse(text, expectedCount: texts.count)
    }

    func testConnection() async throws -> Bool {
        _ = try await translate(texts: ["Hello"], from: "en", to: "zh-Hans")
        return true
    }
}
