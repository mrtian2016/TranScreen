import SwiftUI
import ScreenCaptureKit
import NaturalLanguage

@MainActor
final class AppState: ObservableObject {

    // MARK: - Mode
    enum Mode: Equatable {
        case idle
        case regionSelecting
        case regionTranslating(CGRect)
        case fullScreenMask
        case fullScreenRegionSelecting
    }

    @Published var mode: Mode = .idle {
        didSet { handleModeTransition(from: oldValue, to: mode) }
    }
    @Published var overlayOpacity: Double = 0.5
    @Published var translatedBlocks: [TranslatedBlock] = []
    @Published var hasScreenRecordingPermission = false
    @Published var hasAccessibilityPermission = false
    @Published var isProcessing = false
    @Published var lastError: String?

    // 调试信息
    @Published var debugCapturedSize: CGSize = .zero
    @Published var debugOCRCount: Int = 0

    // MARK: - 子系统
    private(set) var panelController: OverlayPanelController?
    private(set) lazy var hotkeyManager = HotkeyManager(appState: self)

    private let screenCapture = ScreenCaptureManager()
    private let ocrEngine = OCREngine()
    private let textMerger = TextMerger()
    let translationManager = TranslationManager()

    private var fullScreenTask: Task<Void, Never>?
    private let diffDetector = DiffDetector()

    var settings: AppSettings?

    // MARK: - 计算属性
    var sourceLang: String { settings?.sourceLang ?? "auto" }
    var targetLang: String { settings?.targetLang ?? "zh-Hans" }
    var scanInterval: TimeInterval {
        (settings?.powerSavingEnabled == true) ? 5.0 : (settings?.scanInterval ?? 2.0)
    }

    // MARK: - 初始化
    init() {
        checkPermissions()
        setupPanelController()
    }

    private func setupPanelController() {
        panelController = OverlayPanelController(appState: self)
    }

    func checkPermissions() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestPermissions() {
        CGRequestScreenCaptureAccess()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - 状态机转换
    private func handleModeTransition(from old: Mode, to new: Mode) {
        if case .fullScreenMask = old { stopFullScreenTimer() }

        guard let panel = panelController else { return }

        switch new {
        case .idle:
            panel.hide()
            translatedBlocks = []
            isProcessing = false
            lastError = nil

        case .regionSelecting:
            panel.showForSelection()

        case .regionTranslating(let rect):
            panel.showForTranslation(region: rect)
            processRegionCapture(region: rect)

        case .fullScreenMask:
            panel.showFullScreenMask()
            startFullScreenTimer()

        case .fullScreenRegionSelecting:
            panel.showFullScreenForRegionSelection()
        }
    }

    // MARK: - 公开动作
    func enterRegionSelect() {
        // 不做预检查 - ScreenCaptureKit 会在实际截图时由系统处理授权弹窗
        // CGPreflightScreenCaptureAccess 在进程中会缓存结果，授权后需重启才更新
        checkPermissions()  // 仅刷新菜单栏 UI 状态，不阻塞流程
        mode = .regionSelecting
    }

    func toggleFullScreenMask() {
        checkPermissions()
        mode = (mode == .fullScreenMask) ? .idle : .fullScreenMask
    }

    func exitToIdle() {
        mode = .idle
    }

    func adjustOpacity(by delta: Double) {
        overlayOpacity = max(0.1, min(0.9, overlayOpacity + delta))
        settings?.overlayOpacity = overlayOpacity
    }

    func handleRegionSelected(_ rect: CGRect) {
        mode = .regionTranslating(rect)
    }

    // MARK: - 核心 Pipeline：选区截图翻译
    func processRegionCapture(region: CGRect) {
        isProcessing = true
        lastError = nil
        Task {
            do {
                let image = try await screenCapture.captureRegion(region)
                let imageSize = CGSize(width: image.width, height: image.height)
                self.debugCapturedSize = imageSize

                guard image.width > 10, image.height > 10 else {
                    self.lastError = "选区太小（\(image.width)×\(image.height)px），无法识别"
                    self.isProcessing = false
                    self.mode = .idle
                    return
                }

                let ocrResults = try await ocrEngine.recognize(image: image)
                self.debugOCRCount = ocrResults.count
                guard !ocrResults.isEmpty else {
                    self.lastError = "未识别到文字"
                    self.isProcessing = false
                    return
                }

                let textBlocks = ocrResults.map { TextBlock(from: $0) }
                let mergedBlocks = textMerger.merge(blocks: textBlocks)
                let mapper = CoordinateMapper(captureRegion: region, imageSize: imageSize)

                // 先把 OCR 结果作为兜底渲染（即使翻译失败也至少能看到原文）
                let fallback = mergedBlocks.map { mb -> TranslatedBlock in
                    var b = TranslatedBlock(
                        originalText: mb.text,
                        translatedText: "",
                        visionBoundingBox: mb.boundingBox,
                        isVertical: mb.isVertical
                    )
                    b.captureRegion = region
                    b.screenRect = mapper.mapToSwiftUI(visionBox: b.visionBoundingBox)
                    b.fontSize = mapper.adaptiveFontSize(for: b.screenRect, text: b.originalText)
                    return b
                }
                self.translatedBlocks = fallback

                // 把 "auto" 解析为实际语言（Apple Translation 不接受 nil 自动检测）
                let resolvedSource = (sourceLang == "auto")
                    ? Self.detectLanguage(from: mergedBlocks.map(\.text))
                    : sourceLang

                // 再尝试翻译
                do {
                    let translated = try await translationManager.translate(
                        blocks: mergedBlocks,
                        from: resolvedSource,
                        to: targetLang
                    )
                    let rendered = translated.map { block -> TranslatedBlock in
                        var b = block
                        b.captureRegion = region
                        b.screenRect = mapper.mapToSwiftUI(visionBox: b.visionBoundingBox)
                        b.fontSize = mapper.adaptiveFontSize(for: b.screenRect, text: b.translatedText)
                        return b
                    }
                    self.translatedBlocks = rendered
                    self.isProcessing = false
                } catch {
                    // 翻译失败但保留 OCR 结果显示
                    self.lastError = "翻译失败: \(error.localizedDescription)"
                    self.isProcessing = false
                }

            } catch {
                self.lastError = error.localizedDescription
                self.isProcessing = false
                // 截图/OCR 失败才回到 idle
                self.mode = .idle
            }
        }
    }

    // MARK: - 全屏模式定时扫描
    private func startFullScreenTimer() {
        stopFullScreenTimer()
        fullScreenTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(scanInterval))
                guard !Task.isCancelled, mode == .fullScreenMask else { break }
                await processFullScreenCapture()
            }
        }
    }

    private func stopFullScreenTimer() {
        fullScreenTask?.cancel()
        fullScreenTask = nil
        Task { await diffDetector.reset() }
    }

    private func processFullScreenCapture() async {
        do {
            let image = try await screenCapture.captureFullScreen()
            let changedRegions = await diffDetector.detectChangedRegions(current: image)
            guard !changedRegions.isEmpty else { return }

            let ocrResults = try await ocrEngine.recognize(image: image)
            guard !ocrResults.isEmpty else { return }

            let textBlocks = ocrResults.map { TextBlock(from: $0) }
            let mergedBlocks = textMerger.merge(blocks: textBlocks)

            let translated = try await translationManager.translate(
                blocks: mergedBlocks,
                from: sourceLang,
                to: targetLang
            )

            let screenFrame = NSScreen.main?.frame ?? .zero
            let imageSize = CGSize(width: image.width, height: image.height)
            let mapper = CoordinateMapper(captureRegion: screenFrame, imageSize: imageSize)

            let rendered = translated.map { block -> TranslatedBlock in
                var b = block
                b.captureRegion = screenFrame
                b.screenRect = mapper.mapToSwiftUI(visionBox: b.visionBoundingBox)
                b.fontSize = mapper.adaptiveFontSize(for: b.screenRect, text: b.translatedText)
                return b
            }

            self.translatedBlocks = rendered

        } catch {
            print("全屏扫描错误: \(error)")
        }
    }

    // MARK: - 热键和引擎管理
    func startHotkeyMonitoring(with bindings: [HotkeyBinding]) {
        hotkeyManager.loadBindings(bindings)
    }

    func reloadEngines(from configs: [EngineConfig]) {
        translationManager.updateEngines(from: configs)
    }

    // MARK: - 语言检测
    static func detectLanguage(from texts: [String]) -> String {
        let combined = texts.joined(separator: " ")
        guard !combined.isEmpty else { return "en" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(combined)
        guard let lang = recognizer.dominantLanguage else { return "en" }

        // NLLanguage → BCP-47 (Apple Translation / 通用 API)
        switch lang {
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .spanish: return "es"
        case .italian: return "it"
        case .portuguese: return "pt"
        case .russian: return "ru"
        case .dutch: return "nl"
        case .arabic: return "ar"
        case .thai: return "th"
        case .vietnamese: return "vi"
        default: return lang.rawValue
        }
    }
}
