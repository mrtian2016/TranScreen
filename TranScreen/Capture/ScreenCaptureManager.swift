import ScreenCaptureKit
import AppKit
import CoreGraphics

actor ScreenCaptureManager {

    func captureRegion(_ rect: CGRect, excludingWindowIDs: Set<CGWindowID> = []) async throws -> CGImage {
        // 用 NSScreen 作为权威坐标源，避免 SCDisplay.width/height 在不同 macOS 版本
        // 单位（点 vs 像素）不一致导致的尺寸错乱
        guard let nsScreen = NSScreen.screens.first(where: {
            $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY))
        }) ?? NSScreen.main ?? NSScreen.screens.first else {
            throw CaptureError.noDisplay
        }

        let scaleFactor = nsScreen.backingScaleFactor
        let screenW = nsScreen.frame.width   // points
        let screenH = nsScreen.frame.height  // points

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == nsScreen.displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let excludedWindows = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        // 输出尺寸明确按像素：逻辑点 × backing scale
        config.width = Int(screenW * scaleFactor)
        config.height = Int(screenH * scaleFactor)
        config.scalesToFit = false
        config.colorSpaceName = CGColorSpace.sRGB

        let fullImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        #if DEBUG
        print("[Capture] screen=\(screenW)x\(screenH)pt scale=\(scaleFactor) image=\(fullImage.width)x\(fullImage.height)px region=\(rect)")
        #endif

        // 裁剪到选区
        let relX = rect.origin.x - nsScreen.frame.origin.x
        let relYFromBottom = rect.origin.y - nsScreen.frame.origin.y

        let pxX = relX * scaleFactor
        let pxY = (screenH - relYFromBottom - rect.height) * scaleFactor
        let pxW = rect.width * scaleFactor
        let pxH = rect.height * scaleFactor

        let imgW = CGFloat(fullImage.width)
        let imgH = CGFloat(fullImage.height)
        let clampedX = max(0, min(imgW - 1, pxX))
        let clampedY = max(0, min(imgH - 1, pxY))
        let clampedW = max(1, min(pxW, imgW - clampedX))
        let clampedH = max(1, min(pxH, imgH - clampedY))

        let cropRect = CGRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
        guard let cropped = fullImage.cropping(to: cropRect) else {
            throw CaptureError.captureFailed("裁剪失败")
        }

        #if DEBUG
        print("[Capture] cropped=\(cropped.width)x\(cropped.height)px from \(cropRect)")
        #endif

        return cropped
    }

    func captureFullScreen() async throws -> CGImage {
        guard let nsScreen = NSScreen.main ?? NSScreen.screens.first else {
            throw CaptureError.noDisplay
        }
        let scaleFactor = nsScreen.backingScaleFactor

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == nsScreen.displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(nsScreen.frame.width * scaleFactor)
        config.height = Int(nsScreen.frame.height * scaleFactor)
        config.scalesToFit = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    enum CaptureError: Error, LocalizedError {
        case noDisplay
        case captureFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "无法找到屏幕"
            case .captureFailed(let msg): return "截图失败: \(msg)"
            }
        }
    }
}

extension SCDisplay {
    var scaleFactor: CGFloat {
        let nsScreen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
        return nsScreen?.backingScaleFactor ?? 2.0
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
