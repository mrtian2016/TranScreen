import Foundation

actor TranslationCache {
    private struct CacheKey: Hashable {
        let text: String
        let sourceLang: String
        let targetLang: String
    }

    private var cache: [CacheKey: String] = [:]
    private var accessOrder: [CacheKey] = []
    private let maxSize: Int

    init(maxSize: Int = 500) {
        self.maxSize = maxSize
    }

    func get(_ text: String, from source: String, to target: String) -> String? {
        let key = CacheKey(text: text, sourceLang: source, targetLang: target)
        guard let value = cache[key] else { return nil }
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        return value
    }

    func set(_ text: String, translation: String, from source: String, to target: String) {
        let key = CacheKey(text: text, sourceLang: source, targetLang: target)
        cache[key] = translation
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        if cache.count > maxSize {
            let evicted = accessOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}
