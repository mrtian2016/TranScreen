import SwiftUI
import ScreenCaptureKit
import NaturalLanguage
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {

    // MARK: - Mode
    enum Mode: Equatable {
        case idle
        case regionSelecting
        case regionTranslating(CGRect)
        case realtimeActive
        case realtimeSelecting
    }

    struct RealtimeRegion: Identifiable, Equatable {
        let id: UUID
        var screenRegion: CGRect
        var translatedBlocks: [TranslatedBlock]
        var lastTextSignature: String
        var isProcessing: Bool
        var toolbarOffset: CGSize
        var lastCapturedImage: CGImage?
        var showingOriginal: Bool
        var displayNumber: Int

        init(screenRegion: CGRect, displayNumber: Int) {
            self.id = UUID()
            self.screenRegion = screenRegion
            self.translatedBlocks = []
            self.lastTextSignature = ""
            self.isProcessing = true
            self.toolbarOffset = .zero
            self.lastCapturedImage = nil
            self.showingOriginal = false
            self.displayNumber = displayNumber
        }

        static func == (lhs: RealtimeRegion, rhs: RealtimeRegion) -> Bool {
            lhs.id == rhs.id
        }
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
    @Published var showingOriginal = false
    @Published var selectedRegion: CGRect = .zero
    @Published var realtimeRegions: [RealtimeRegion] = []
    @Published var regionToolbarOffset: CGSize = .zero

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

    private var realtimeTask: Task<Void, Never>?
    private var isRealtimeRefreshInFlight = false
    private var realtimePanelControllers: [UUID: RealtimeRegionPanelController] = [:]
    private let diffDetector = DiffDetector()

    /// Holds the clean original capture so the screenshot button saves the
    /// pre-overlay image (no dimming, no translation labels). Cleared on idle.
    private var lastCapturedImage: CGImage?

    var settings: AppSettings?

    // MARK: - 计算属性
    var sourceLang: String { settings?.sourceLang ?? "auto" }
    var targetLang: String { settings?.targetLang ?? "zh-Hans" }
    var scanInterval: TimeInterval {
        max(0.1, min(10.0, settings?.scanInterval ?? 2.0))
    }
    var selectionBorderColorHex: String { settings?.selectionBorderColorHex ?? "#000000" }
    var selectionBorderStyle: String { settings?.selectionBorderStyle ?? "corners" }
    var selectionBorderLineWidth: CGFloat { CGFloat(settings?.selectionBorderLineWidth ?? 1.4) }
    var regionToolbarOpacity: Double { settings?.regionToolbarOpacity ?? 0.9 }
    var realtimeToolbarOpacity: Double { settings?.realtimeToolbarOpacity ?? 0.5 }
    var realtimeBadgeColorHex: String { settings?.realtimeBadgeColorHex ?? "#111111" }
    var realtimeBadgeTextColorHex: String { settings?.realtimeBadgeTextColorHex ?? "#FFFFFF" }
    var realtimeBadgeOpacity: Double { settings?.realtimeBadgeOpacity ?? 0.8 }
    var realtimeBadgeFontSize: CGFloat { CGFloat(settings?.realtimeBadgeFontSize ?? 11.0) }

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
        guard let panel = panelController else { return }

        switch new {
        case .idle:
            panel.hide()
            translatedBlocks = []
            lastCapturedImage = nil
            isProcessing = false
            lastError = nil
            clearRealtimeRegions()

        case .regionSelecting:
            panel.showForSelection()

        case .regionTranslating(let rect):
            panel.showForTranslation(region: rect)
            processRegionCapture(region: rect)

        case .realtimeActive:
            panel.hide()
            if realtimeRegions.isEmpty {
                stopRealtimeTimer()
            }

        case .realtimeSelecting:
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
        enterRealtimeSelect()
    }

    func enterRealtimeSelect() {
        checkPermissions()
        guard realtimeRegions.count < 8 else {
            lastError = "实时翻译最多支持 8 个区域"
            mode = realtimeRegions.isEmpty ? .idle : .realtimeActive
            return
        }
        mode = .realtimeSelecting
    }

    func exitToIdle() {
        mode = .idle
    }

    func adjustOpacity(by delta: Double) {
        guard let settings else { return }
        objectWillChange.send()
        settings.regionToolbarOpacity = max(0.2, min(1.0, settings.regionToolbarOpacity + delta))
        settings.realtimeToolbarOpacity = max(0.2, min(1.0, settings.realtimeToolbarOpacity + delta))
    }

    func handleRegionSelected(_ rect: CGRect) {
        selectedRegion = rect
        showingOriginal = false
        regionToolbarOffset = .zero
        mode = .regionTranslating(rect)
    }

    func handleRealtimeRegionSelected(_ rect: CGRect) {
        addRealtimeRegion(rect)
        mode = .realtimeActive
    }

    func copyDisplayedText() {
        let text = translatedBlocks.map {
            showingOriginal ? $0.originalText : ($0.translatedText.isEmpty ? $0.originalText : $0.translatedText)
        }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @discardableResult
    func saveScreenshot(of region: CGRect) -> Bool {
        guard let cgImage = lastCapturedImage else {
            lastError = "无可保存的截图"
            return false
        }

        guard let imageToSave = screenshotImage(
            baseImage: cgImage,
            region: region,
            blocks: translatedBlocks,
            showingOriginal: showingOriginal
        ) else { return false }

        return writeScreenshot(image: imageToSave, suffix: showingOriginal ? "original" : "translated")
    }

    private func screenshotImage(
        baseImage: CGImage,
        region: CGRect,
        blocks: [TranslatedBlock],
        showingOriginal: Bool
    ) -> CGImage? {
        if showingOriginal || blocks.isEmpty {
            return baseImage
        }
        guard let rendered = renderDisplayedRegionScreenshot(
            baseImage: baseImage,
            region: region,
            blocks: blocks,
            showingOriginal: showingOriginal
        ) else {
            lastError = "无法生成译文截图"
            return nil
        }
        return rendered
    }

    private func writeScreenshot(image: CGImage, suffix: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "TranScreen_\(suffix)_\(formatter.string(from: Date())).png"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let url = downloadsURL.appendingPathComponent(filename)

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            lastError = "无法创建图片输出"
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            lastError = nil
            return true
        } else {
            lastError = "截图保存失败"
            return false
        }
    }

    private func renderDisplayedRegionScreenshot(
        baseImage: CGImage,
        region: CGRect,
        blocks: [TranslatedBlock],
        showingOriginal: Bool
    ) -> CGImage? {
        let imageSize = CGSize(width: region.width, height: region.height)
        let scale = CGFloat(baseImage.width) / max(region.width, 1)
        let nsImage = NSImage(cgImage: baseImage, size: imageSize)
        let screen = OverlayCoordinateSpace.screen(containing: region)
        let localRegion = OverlayCoordinateSpace.localRect(for: region, in: screen)
        let content = DisplayedRegionScreenshotView(
            baseImage: nsImage,
            blocks: blocks,
            showingOriginal: showingOriginal,
            localRegion: localRegion
        )
        .frame(width: imageSize.width, height: imageSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(imageSize)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    // MARK: - 核心 Pipeline：选区截图翻译 / 实时翻译共用

    private struct BlockRenderMetadata {
        let lineBoxes: [CGRect]
        let bg: (Double, Double, Double)
        let edges: LineGeometry?
    }

    private struct CaptureAnalysis {
        let region: CGRect
        let image: CGImage
        let imageSize: CGSize
        let mapper: CoordinateMapper
        let mergedBlocks: [MergedTextBlock]
        let metadata: [UUID: BlockRenderMetadata]
        let signature: String
    }

    func processRegionCapture(region: CGRect) {
        isProcessing = true
        lastError = nil
        Task {
            do {
                let image = try await screenCapture.captureRegion(region)
                self.debugCapturedSize = CGSize(width: image.width, height: image.height)
                self.lastCapturedImage = image

                let analysis = try await analyzeCapture(image: image, region: region)
                self.debugOCRCount = analysis.mergedBlocks.reduce(0) { $0 + $1.lines.count }
                guard !analysis.mergedBlocks.isEmpty else {
                    self.lastError = "未识别到文字"
                    self.isProcessing = false
                    return
                }

                let (renderedByRegion, error) = await translateAndRender(analyses: [analysis])
                self.translatedBlocks = renderedByRegion[analysis.region] ?? []
                if let error {
                    self.lastError = "翻译失败: \(error.localizedDescription)"
                }
                self.isProcessing = false
            } catch {
                self.lastError = error.localizedDescription
                self.isProcessing = false
                self.mode = .idle
            }
        }
    }

    private func analyzeCapture(image: CGImage, region: CGRect) async throws -> CaptureAnalysis {
        guard image.width > 10, image.height > 10 else {
            throw ScreenCaptureManager.CaptureError.captureFailed("选区太小（\(image.width)×\(image.height)px），无法识别")
        }

        let imageSize = CGSize(width: image.width, height: image.height)
        let mapper = CoordinateMapper(captureRegion: region, imageSize: imageSize)
        let ocrResults = try await ocrEngine.recognize(image: image)
        let textBlocks = ocrResults.map { TextBlock(from: $0) }
        let regions = RegionSegmenter().segment(blocks: textBlocks)
        let edgeDetector = EdgeDetector()

        var mergedBlocks: [MergedTextBlock] = []
        var metadata: [UUID: BlockRenderMetadata] = [:]

        for textRegion in regions {
            let merged = textMerger.merge(blocks: textRegion.blocks)
            for mb in merged {
                let bg = BackgroundSampler.sampleBackgroundColor(image: image, normalizedBox: mb.boundingBox)
                metadata[mb.id] = BlockRenderMetadata(
                    lineBoxes: mb.lines.map(\.boundingBox),
                    bg: bg,
                    edges: edgeDetector.detectLineEdges(blocks: mb.lines)
                )
            }
            mergedBlocks.append(contentsOf: merged)
        }

        let signature = mergedBlocks.map(\.text).joined(separator: "\n")
        return CaptureAnalysis(
            region: region,
            image: image,
            imageSize: imageSize,
            mapper: mapper,
            mergedBlocks: mergedBlocks,
            metadata: metadata,
            signature: signature
        )
    }

    private func translateAndRender(analyses: [CaptureAnalysis]) async -> (rendered: [CGRect: [TranslatedBlock]], error: Error?) {
        let allBlocks = analyses.flatMap(\.mergedBlocks)
        guard !allBlocks.isEmpty else { return ([:], nil) }

        let resolvedSource = (sourceLang == "auto")
            ? Self.detectLanguage(from: allBlocks.map(\.text))
            : sourceLang

        do {
            let translated = try await translationManager.translate(
                blocks: allBlocks,
                from: resolvedSource,
                to: targetLang
            )
            return (renderTranslatedBlocks(translated, analyses: analyses), nil)
        } catch {
            let fallback = allBlocks.map {
                TranslatedBlock(
                    originalText: $0.text,
                    translatedText: "",
                    visionBoundingBox: $0.boundingBox,
                    isVertical: $0.isVertical
                )
            }
            return (renderTranslatedBlocks(fallback, analyses: analyses), error)
        }
    }

    private func renderTranslatedBlocks(_ translated: [TranslatedBlock], analyses: [CaptureAnalysis]) -> [CGRect: [TranslatedBlock]] {
        var rendered: [CGRect: [TranslatedBlock]] = [:]
        var cursor = 0

        for analysis in analyses {
            let count = analysis.mergedBlocks.count
            guard count > 0 else {
                rendered[analysis.region] = []
                continue
            }

            let translatedSlice = Array(translated[cursor..<min(cursor + count, translated.count)])
            let sourceSlice = Array(analysis.mergedBlocks[0..<min(count, analysis.mergedBlocks.count)])
            cursor += count

            rendered[analysis.region] = zip(sourceSlice, translatedSlice).map { source, block in
                renderBlock(block, source: source, analysis: analysis)
            }
        }

        return rendered
    }

    private func renderBlock(_ block: TranslatedBlock, source: MergedTextBlock, analysis: CaptureAnalysis) -> TranslatedBlock {
        var b = block
        b.captureRegion = analysis.region
        b.screenRect = analysis.mapper.mapToSwiftUI(visionBox: b.visionBoundingBox)

        let meta = analysis.metadata[source.id]
        let lineBoxes = meta?.lineBoxes ?? source.lines.map(\.boundingBox)
        b.fontSize = analysis.mapper.adaptiveFontSize(forLineBoxes: lineBoxes.isEmpty ? [b.visionBoundingBox] : lineBoxes)
        b.screenLineRects = lineBoxes.map { analysis.mapper.mapToSwiftUI(visionBox: $0) }

        let bg = meta?.bg ?? (1, 1, 1)
        b.bgRed = bg.0; b.bgGreen = bg.1; b.bgBlue = bg.2
        let (tr, tg, tb) = BackgroundSampler.sampleTextColor(
            image: analysis.image,
            normalizedBoxes: lineBoxes.isEmpty ? [b.visionBoundingBox] : lineBoxes,
            background: bg
        )
        b.textR = tr; b.textG = tg; b.textB = tb

        if let edges = meta?.edges {
            b.lineEdges = (left: edges.leftEdge, right: edges.rightEdge)
        }
        return b
    }

    // MARK: - 实时翻译

    private func stopRealtimeTimer() {
        realtimeTask?.cancel()
        realtimeTask = nil
        Task { await diffDetector.reset() }
    }

    func noteRealtimeUserActivity() {
        guard !realtimeRegions.isEmpty else { return }
        realtimeTask?.cancel()
        realtimeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(scanInterval))
            guard !Task.isCancelled, !realtimeRegions.isEmpty else { return }
            await refreshRealtimeRegions(force: false)
        }
    }

    private func addRealtimeRegion(_ region: CGRect) {
        guard realtimeRegions.count < 8 else {
            lastError = "实时翻译最多支持 8 个区域"
            return
        }
        let realtimeRegion = RealtimeRegion(screenRegion: region, displayNumber: nextRealtimeDisplayNumber())
        realtimeRegions.append(realtimeRegion)
        let controller = RealtimeRegionPanelController(appState: self, regionID: realtimeRegion.id, screenRegion: region)
        realtimePanelControllers[realtimeRegion.id] = controller
        controller.show()
        layoutRealtimeToolbars()
        Task { @MainActor in
            await refreshRealtimeRegions(ids: [realtimeRegion.id], force: true)
        }
    }

    func realtimeRegion(id: UUID) -> RealtimeRegion? {
        realtimeRegions.first { $0.id == id }
    }

    func updateRealtimeToolbarOffset(id: UUID, offset: CGSize) {
        guard let index = realtimeRegions.firstIndex(where: { $0.id == id }) else { return }
        realtimeRegions[index].toolbarOffset = offset
        layoutRealtimeToolbars()
    }

    func toggleRealtimeRegionOriginal(id: UUID) {
        guard let index = realtimeRegions.firstIndex(where: { $0.id == id }) else { return }
        realtimeRegions[index].showingOriginal.toggle()
    }

    func setRealtimeRegionShowingOriginal(id: UUID, showingOriginal: Bool) {
        guard let index = realtimeRegions.firstIndex(where: { $0.id == id }) else { return }
        realtimeRegions[index].showingOriginal = showingOriginal
    }

    func copyRealtimeRegionText(id: UUID) {
        guard let region = realtimeRegion(id: id) else { return }
        let text = region.translatedBlocks.map {
            region.showingOriginal ? $0.originalText : ($0.translatedText.isEmpty ? $0.originalText : $0.translatedText)
        }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @discardableResult
    func saveRealtimeScreenshot(id: UUID) -> Bool {
        guard let region = realtimeRegion(id: id), let image = region.lastCapturedImage else {
            lastError = "无可保存的实时截图"
            return false
        }
        guard let imageToSave = screenshotImage(
            baseImage: image,
            region: region.screenRegion,
            blocks: region.translatedBlocks,
            showingOriginal: region.showingOriginal
        ) else { return false }

        let suffix = region.showingOriginal ? "realtime_original_\(region.displayNumber)" : "realtime_translated_\(region.displayNumber)"
        return writeScreenshot(image: imageToSave, suffix: suffix)
    }

    func updateRealtimeToolbarSize(id: UUID, size: CGSize) {
        if realtimePanelControllers[id]?.updateToolbarSize(size) == true {
            layoutRealtimeToolbars()
        }
    }

    func finishRealtimeToolbarDrag(id: UUID, frame: CGRect) {
        guard let index = realtimeRegions.firstIndex(where: { $0.id == id }),
              let controller = realtimePanelControllers[id] else { return }
        realtimeRegions[index].toolbarOffset = controller.offset(forToolbarOrigin: frame.origin)
        layoutRealtimeToolbars()
    }

    func realtimeToolbarContainsEventLocation(_ location: CGPoint) -> Bool {
        let toolbarFrames = realtimePanelControllers.values.map(\.toolbarFrame)
        if toolbarFrames.contains(where: { $0.contains(location) }) {
            return true
        }
        for screen in NSScreen.screens {
            let flipped = CGPoint(x: location.x, y: screen.frame.maxY - (location.y - screen.frame.minY))
            if toolbarFrames.contains(where: { $0.contains(flipped) }) {
                return true
            }
        }
        return false
    }

    func closeRealtimeRegion(id: UUID) {
        realtimePanelControllers[id]?.close()
        realtimePanelControllers[id] = nil
        realtimeRegions.removeAll { $0.id == id }
        layoutRealtimeToolbars()
        if realtimeRegions.isEmpty {
            stopRealtimeTimer()
            mode = .idle
        }
    }

    private func clearRealtimeRegions() {
        stopRealtimeTimer()
        for controller in realtimePanelControllers.values {
            controller.close()
        }
        realtimePanelControllers.removeAll()
        realtimeRegions.removeAll()
    }

    private func refreshRealtimeRegions(ids: [UUID]? = nil, force: Bool) async {
        guard !isRealtimeRefreshInFlight else { return }
        let targetIDs = ids ?? realtimeRegions.map(\.id)
        guard !targetIDs.isEmpty else { return }

        isRealtimeRefreshInFlight = true
        defer { isRealtimeRefreshInFlight = false }
        let excludedWindowIDs = realtimeCaptureExcludedWindowIDs()

        for id in targetIDs {
            if let index = realtimeRegions.firstIndex(where: { $0.id == id }) {
                realtimeRegions[index].isProcessing = true
            }
        }

        var analyses: [(id: UUID, analysis: CaptureAnalysis)] = []
        for id in targetIDs {
            guard let index = realtimeRegions.firstIndex(where: { $0.id == id }) else { continue }
            let region = realtimeRegions[index].screenRegion
            do {
                let image = try await screenCapture.captureRegion(region, excludingWindowIDs: excludedWindowIDs)
                let analysis = try await analyzeCapture(image: image, region: region)
                realtimeRegions[index].lastCapturedImage = image

                if force || analysis.signature != realtimeRegions[index].lastTextSignature {
                    analyses.append((id, analysis))
                } else {
                    realtimeRegions[index].isProcessing = false
                }
            } catch {
                realtimeRegions[index].isProcessing = false
                lastError = error.localizedDescription
            }
        }

        guard !analyses.isEmpty else { return }

        let (rendered, error) = await translateAndRender(analyses: analyses.map(\.analysis))
        if let error {
            lastError = "实时翻译失败: \(error.localizedDescription)"
        }

        for item in analyses {
            guard let index = realtimeRegions.firstIndex(where: { $0.id == item.id }) else { continue }
            realtimeRegions[index].translatedBlocks = rendered[item.analysis.region] ?? []
            if error == nil {
                realtimeRegions[index].lastTextSignature = item.analysis.signature
            }
            realtimeRegions[index].isProcessing = false
        }
    }

    private func realtimeCaptureExcludedWindowIDs() -> Set<CGWindowID> {
        Set(realtimePanelControllers.values.flatMap(\.windowIDs))
    }

    private func nextRealtimeDisplayNumber() -> Int {
        let used = Set(realtimeRegions.map(\.displayNumber))
        return (1...8).first { !used.contains($0) } ?? min(realtimeRegions.count + 1, 8)
    }

    private func layoutRealtimeToolbars() {
        let orderedRegions = realtimeRegions.sorted { lhs, rhs in
            lhs.displayNumber < rhs.displayNumber
        }
        var placedFrames: [CGRect] = []

        for region in orderedRegions {
            guard let controller = realtimePanelControllers[region.id] else { continue }
            var frame = controller.toolbarFrame(forOffset: region.toolbarOffset)
            frame = clamp(frame: frame, to: OverlayCoordinateSpace.screen(containing: region.screenRegion).frame, margin: 4)

            let baseFrame = frame
            let gap: CGFloat = 6
            var column = 0
            var row = 0
            while placedFrames.contains(where: { $0.insetBy(dx: -gap, dy: -gap).intersects(frame) }) {
                row += 1
                frame.origin.y = baseFrame.origin.y + CGFloat(row) * (frame.height + gap)

                let screenFrame = OverlayCoordinateSpace.screen(containing: region.screenRegion).frame
                if frame.maxY > screenFrame.maxY - gap {
                    column += 1
                    row = 0
                    frame.origin.x = baseFrame.origin.x - CGFloat(column) * (frame.width + gap)
                    frame.origin.y = baseFrame.origin.y
                }
                frame = clamp(frame: frame, to: OverlayCoordinateSpace.screen(containing: region.screenRegion).frame, margin: 4)
                if column > 8 { break }
            }

            controller.setToolbarFrame(frame)
            placedFrames.append(frame)
        }
    }

    private func clamp(frame: CGRect, to screenFrame: CGRect, margin: CGFloat) -> CGRect {
        var result = frame
        result.origin.x = max(screenFrame.minX + margin, min(result.origin.x, screenFrame.maxX - result.width - margin))
        result.origin.y = max(screenFrame.minY + margin, min(result.origin.y, screenFrame.maxY - result.height - margin))
        return result
    }

    // MARK: - 热键和引擎管理
    func startHotkeyMonitoring(with bindings: [HotkeyBinding]) {
        hotkeyManager.loadBindings(bindings)
    }

    func pauseHotkeyMonitoringForRecording() {
        hotkeyManager.unregister()
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

private struct DisplayedRegionScreenshotView: View {
    let baseImage: NSImage
    let blocks: [TranslatedBlock]
    let showingOriginal: Bool
    let localRegion: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: baseImage)
                .resizable()
                .interpolation(.high)
                .frame(width: localRegion.width, height: localRegion.height)

            ForEach(blocks) { block in
                let maxW = max(30, block.screenRect.width)
                let xOffset = clamp(
                    block.screenRect.minX - localRegion.minX,
                    min: 0,
                    max: max(0, localRegion.width - maxW)
                )
                let yOffset = max(0, block.screenRect.minY - localRegion.minY - 1)

                ForEach(Array(textCoverRects(for: block).enumerated()), id: \.offset) { _, rect in
                    background(for: block)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX - localRegion.minX, y: rect.minY - localRegion.minY)
                }

                translatedLabel(for: block)
                    .frame(width: maxW, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(background(for: block))
                    .offset(x: xOffset, y: yOffset)
            }
        }
        .frame(width: localRegion.width, height: localRegion.height, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private func translatedLabel(for block: TranslatedBlock) -> some View {
        let displayText = showingOriginal
            ? block.originalText
            : (block.translatedText.isEmpty ? block.originalText : block.translatedText)

        Text(displayText.isEmpty ? "[空]" : displayText)
            .font(.system(size: block.fontSize, weight: .regular, design: .default))
            .foregroundStyle(textColor(for: block))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .rotationEffect(block.isVertical ? .degrees(90) : .degrees(0))
    }

    private func background(for block: TranslatedBlock) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(red: block.bgRed, green: block.bgGreen, blue: block.bgBlue))
    }

    private func textCoverRects(for block: TranslatedBlock) -> [CGRect] {
        let rects = block.screenLineRects.isEmpty ? [block.screenRect] : block.screenLineRects
        return rects.map {
            $0.insetBy(dx: -3, dy: -2)
        }
    }

    private func textColor(for block: TranslatedBlock) -> Color {
        let hasTextSample = block.textR > 0.01 || block.textG > 0.01 || block.textB > 0.01
        if hasTextSample {
            return Color(red: block.textR, green: block.textG, blue: block.textB)
        }
        return block.isLightBackground ? .black : .white
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}
