import AppKit
import Foundation

enum DeliverableError: LocalizedError {
    case invalidFormat(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let format):
            return "Unsupported deliverable format '\(format)'. Use md, txt, or pdf."
        case .writeFailed(let detail):
            return "Failed to write deliverable: \(detail)"
        }
    }
}

final class DeliverableService {
    static let shared = DeliverableService()

    private let folderName = "JARVIS Output"

    var outputDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    func save(content: String, format: String, filename: String) throws -> URL {
        try ensureOutputDirectory()

        let normalizedFormat = format.lowercased()
        let fileExtension: String
        switch normalizedFormat {
        case "md":
            fileExtension = "md"
        case "txt":
            fileExtension = "txt"
        case "pdf":
            fileExtension = "pdf"
        default:
            throw DeliverableError.invalidFormat(format)
        }

        let baseName = Self.sanitizeFilename(filename)
        let destination = Self.uniqueURL(
            in: outputDirectory,
            baseName: baseName,
            fileExtension: fileExtension
        )

        switch normalizedFormat {
        case "md", "txt":
            do {
                try content.write(to: destination, atomically: true, encoding: .utf8)
            } catch {
                throw DeliverableError.writeFailed(error.localizedDescription)
            }
        case "pdf":
            try Self.writePDF(content: content, to: destination)
        default:
            throw DeliverableError.invalidFormat(format)
        }

        return destination
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.open(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func ensureOutputDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DeliverableError.writeFailed(error.localizedDescription)
        }
    }

    private static func sanitizeFilename(_ name: String) -> String {
        var sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        sanitized = sanitized.components(separatedBy: invalid).joined(separator: "-")
        sanitized = sanitized.replacingOccurrences(of: "..", with: ".")

        for ext in ["pdf", "md", "txt"] {
            if sanitized.lowercased().hasSuffix(".\(ext)") {
                sanitized = String(sanitized.dropLast(ext.count + 1))
            }
        }

        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Deliverable" : sanitized
    }

    private static func uniqueURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(fileExtension)")
            counter += 1
        }
        return candidate
    }

    private static func plainText(from content: String) -> String {
        var text = content
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(
            of: #"(?m)^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        return text
    }

    private static func writePDF(content: String, to url: URL) throws {
        let pageWidth = CGFloat(612)
        let pageHeight = CGFloat(792)
        let margin = CGFloat(54)
        let printableSize = NSSize(width: pageWidth - margin * 2, height: pageHeight - margin * 2)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        let attributed = NSAttributedString(string: plainText(from: content), attributes: attributes)

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw DeliverableError.writeFailed("Could not create PDF context.")
        }

        var didDrawPage = false
        while true {
            let textContainer = NSTextContainer(size: printableSize)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            if glyphRange.length == 0 {
                break
            }

            context.beginPDFPage(nil)
            didDrawPage = true

            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            let origin = NSPoint(x: margin, y: margin)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()

            if glyphRange.upperBound >= layoutManager.numberOfGlyphs {
                break
            }
        }

        if !didDrawPage {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }

        context.closePDF()

        do {
            try Data(referencing: pdfData).write(to: url)
        } catch {
            throw DeliverableError.writeFailed(error.localizedDescription)
        }
    }
}
