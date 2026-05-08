import Foundation
import SwiftUI
#if canImport(Translation)
@preconcurrency import Translation
#endif

// MARK: - Bridge：桥接 Apple TranslationSession 与 async/await
@MainActor
final class AppleTranslationBridge: ObservableObject {
    static let shared = AppleTranslationBridge()

    struct Pending: Sendable {
        let texts: [String]
        let continuation: CheckedContinuation<[String], Error>
    }

    @available(macOS 15, *)
    @Published var configuration: TranslationSession.Configuration?

    @Published var lastSetupError: String?

    private var pending: Pending?
    private var lastSource = ""
    private var lastTarget = ""

    private init() {}

    @available(macOS 15, *)
    func translate(texts: [String], from source: String, to target: String) async throws -> [String] {
        // 60 秒整体超时，防止系统语言包对话框挂起永远不返回
        try await withThrowingTaskGroup(of: [String].self) { group in
            group.addTask { [weak self] in
                try await self?.translateInternal(texts: texts, from: source, to: target) ?? []
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw TranslationError.invalidResponse("Apple 翻译超时（可能需要先下载语言包）")
            }
            guard let result = try await group.next() else {
                throw TranslationError.allEnginesFailed
            }
            group.cancelAll()
            return result
        }
    }

    @available(macOS 15, *)
    private func translateInternal(texts: [String], from source: String, to target: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String], Error>) in
            // 取消未完成的旧请求
            pending?.continuation.resume(throwing: TranslationError.notAvailable)
            pending = Pending(texts: texts, continuation: cont)

            if source != lastSource || target != lastTarget || configuration == nil {
                lastSource = source
                lastTarget = target
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target)
                )
            } else {
                configuration?.invalidate()
            }
        }
    }

    func takePending() -> Pending? {
        let p = pending
        pending = nil
        return p
    }

    // 主动触发语言包准备 / 下载（由设置页 UI 调用）
    // 内部走 translate(["__prepare__"]) 路径触发 .translationTask 中的 prepareTranslation()
    @available(macOS 15, *)
    func prepareLanguagePack(from source: String, to target: String) async throws {
        _ = try await translate(texts: ["Hello"], from: source, to: target)
    }
}

// MARK: - Provider：在 .translationTask 内部完成所有翻译
@available(macOS 15, *)
struct AppleTranslationProvider: View {
    @ObservedObject var bridge: AppleTranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .opacity(0.001)  // 必须可见才能触发 .translationTask；近乎透明
            .allowsHitTesting(false)
            .translationTask(bridge.configuration) { session in
                guard let pending = bridge.takePending() else { return }
                do {
                    // 先确保语言包就绪（首次会触发系统下载对话框）
                    try await session.prepareTranslation()
                    var results: [String] = []
                    for text in pending.texts {
                        let response = try await session.translate(text)
                        results.append(response.targetText)
                    }
                    pending.continuation.resume(returning: results)
                } catch {
                    pending.continuation.resume(throwing: error)
                }
            }
    }
}

// MARK: - Engine 实现
struct AppleTranslationEngine: TranslationEngine {
    let engineType = EngineType.apple
    let configID: UUID

    init(configID: UUID = UUID()) {
        self.configID = configID
    }

    func translate(texts: [String], from sourceLang: String, to targetLang: String) async throws -> [String] {
        guard #available(macOS 15, *) else {
            throw TranslationError.notAvailable
        }
        // Apple Translation 不支持 "auto" — AppState 会先用 NLLanguageRecognizer 解析
        let source = (sourceLang == "auto") ? "en" : sourceLang
        return try await AppleTranslationBridge.shared.translate(
            texts: texts, from: source, to: targetLang
        )
    }

    func testConnection() async throws -> Bool {
        guard #available(macOS 15, *) else { return false }
        let result = try await translate(texts: ["Hello"], from: "en", to: "zh-Hans")
        return !result.isEmpty && !(result.first?.isEmpty ?? true)
    }
}
