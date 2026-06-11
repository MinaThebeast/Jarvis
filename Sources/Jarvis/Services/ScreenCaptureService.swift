import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenCaptureError: LocalizedError {
    case captureFailed
    case jpegConversionFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Screen capture failed — enable Screen Recording for JARVIS in System Settings > Privacy & Security."
        case .jpegConversionFailed:
            return "Screen capture failed — enable Screen Recording for JARVIS in System Settings > Privacy & Security."
        }
    }
}

final class ScreenCaptureService {

    private let maxLongestSide: CGFloat = 1536
    private let jpegQuality: CGFloat = 0.7

    func captureFullScreen() throws -> Data {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ScreenCaptureError.captureFailed
        }
        return try encodeJPEG(from: image)
    }

    func captureActiveWindow() throws -> Data {
        if let windowImage = try captureFrontmostWindow() {
            return windowImage
        }
        return try captureFullScreen()
    }

    func jpegBase64(from data: Data) -> String {
        data.base64EncodedString()
    }

    // MARK: - Private

    private func captureFrontmostWindow() throws -> Data? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let frontPID = frontApp.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == frontPID else { continue }
            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }

            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            guard width > 0, height > 0 else { continue }

            guard let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                .bestResolution
            ) else {
                continue
            }

            return try encodeJPEG(from: image)
        }

        return nil
    }

    private func encodeJPEG(from image: CGImage) throws -> Data {
        let scaled = downscaleIfNeeded(image)
        let rep = NSBitmapImageRep(cgImage: scaled)
        guard let jpeg = rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: jpegQuality]
        ) else {
            throw ScreenCaptureError.jpegConversionFailed
        }
        return jpeg
    }

    private func downscaleIfNeeded(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        let longest = max(width, height)
        guard longest > Int(maxLongestSide) else { return image }

        let scale = maxLongestSide / CGFloat(longest)
        let newWidth = Int(CGFloat(width) * scale)
        let newHeight = Int(CGFloat(height) * scale)

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }
}
