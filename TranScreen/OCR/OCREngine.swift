import Vision
import CoreGraphics

struct OCREngine: Sendable {

    struct OCRResult: Sendable {
        let text: String
        let boundingBox: CGRect
        let confidence: Float
    }

    func recognize(
        image: CGImage,
        languages: [String] = ["en-US", "zh-Hans", "zh-Hant", "ja", "ko"]
    ) async throws -> [OCRResult] {
        guard image.width > 10, image.height > 10 else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = languages
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.0

        // 注意：automaticallyDetectsLanguage 会覆盖 recognitionLanguages，
        // 在某些场景下反而识别不出文字。明确不开。

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])

        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []

        #if DEBUG
        print("[OCR] image=\(image.width)x\(image.height) observations=\(observations.count)")
        if observations.isEmpty {
            print("[OCR] No text detected. Languages tried: \(languages)")
        }
        #endif

        return observations.compactMap { obs -> OCRResult? in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            // 阈值放宽到 0.1 — 兼容低对比度 / 小字号场景
            guard candidate.confidence > 0.1 else { return nil }
            return OCRResult(
                text: candidate.string,
                boundingBox: obs.boundingBox,
                confidence: candidate.confidence
            )
        }
    }
}
