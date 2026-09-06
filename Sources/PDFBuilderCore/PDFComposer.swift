import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit

public enum PDFComposerError: LocalizedError {
    case noPages
    case cannotCreateFile
    case cannotReadSource(String)

    public var errorDescription: String? {
        switch self {
        case .noPages:
            "There are no pages to save."
        case .cannotCreateFile:
            "The PDF file could not be created."
        case let .cannotReadSource(name):
            "The source file “\(name)” could not be read."
        }
    }
}

public enum PDFComposer {
    public static let a4Size = CGSize(width: 595.28, height: 841.89)

    public static func write(pages: [InputPage], format: PageFormat, to outputURL: URL) throws {
        guard !pages.isEmpty else { throw PDFComposerError.noPages }

        var firstBox = CGRect(origin: .zero, size: pageSize(for: pages[0], format: format))
        let metadata: [CFString: Any] = [
            kCGPDFContextTitle: outputURL.deletingPathExtension().lastPathComponent,
            kCGPDFContextCreator: "PDF Builder"
        ]

        guard let context = CGContext(
            outputURL as CFURL,
            mediaBox: &firstBox,
            metadata as CFDictionary
        ) else {
            throw PDFComposerError.cannotCreateFile
        }

        var pdfCache: [URL: PDFDocument] = [:]

        for page in pages {
            let size = pageSize(for: page, format: format)
            var mediaBox = CGRect(origin: .zero, size: size)
            let mediaBoxData = NSData(
                bytes: &mediaBox,
                length: MemoryLayout<CGRect>.size
            )
            context.beginPDFPage(
                [kCGPDFContextMediaBox as String: mediaBoxData] as CFDictionary
            )

            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)

            if let pageIndex = page.sourcePageIndex {
                let document: PDFDocument
                if let cached = pdfCache[page.sourceURL] {
                    document = cached
                } else if let loaded = PDFDocument(url: page.sourceURL) {
                    pdfCache[page.sourceURL] = loaded
                    document = loaded
                } else {
                    context.endPDFPage()
                    context.closePDF()
                    throw PDFComposerError.cannotReadSource(page.sourceURL.lastPathComponent)
                }

                guard let pdfPage = document.page(at: pageIndex) else {
                    context.endPDFPage()
                    context.closePDF()
                    throw PDFComposerError.cannotReadSource(page.displayName)
                }
                draw(pdfPage: pdfPage, sourceSize: page.imageSize, in: mediaBox, context: context)
            } else {
                guard let image = loadOrientedImage(at: page.sourceURL, sourceSize: page.imageSize) else {
                    context.endPDFPage()
                    context.closePDF()
                    throw PDFComposerError.cannotReadSource(page.sourceURL.lastPathComponent)
                }
                draw(image: image, sourceSize: page.imageSize, in: mediaBox, context: context)
            }

            context.endPDFPage()
        }

        context.closePDF()
    }

    public static func pageSize(for page: InputPage, format: PageFormat) -> CGSize {
        let source = page.imageSize
        guard source.width > 0, source.height > 0 else { return a4Size }

        switch format {
        case .a4:
            return source.width > source.height
                ? CGSize(width: a4Size.height, height: a4Size.width)
                : a4Size
        case .automatic:
            let longEdge = a4Size.height
            if source.width > source.height {
                return CGSize(width: longEdge, height: longEdge * source.height / source.width)
            }
            return CGSize(width: longEdge * source.width / source.height, height: longEdge)
        }
    }

    private static func draw(image: CGImage, sourceSize: CGSize, in pageRect: CGRect, context: CGContext) {
        let target = aspectFit(sourceSize: sourceSize, in: pageRect)
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: target)
        context.restoreGState()
    }

    private static func draw(pdfPage: PDFPage, sourceSize: CGSize, in pageRect: CGRect, context: CGContext) {
        let target = aspectFit(sourceSize: sourceSize, in: pageRect)
        let sourceBounds = pdfPage.bounds(for: .mediaBox)

        context.saveGState()
        context.translateBy(x: target.minX, y: target.minY)
        context.scaleBy(x: target.width / sourceBounds.width, y: target.height / sourceBounds.height)
        context.translateBy(x: -sourceBounds.minX, y: -sourceBounds.minY)
        pdfPage.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }

    private static func aspectFit(sourceSize: CGSize, in destination: CGRect) -> CGRect {
        let scale = min(destination.width / sourceSize.width, destination.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: destination.midX - size.width / 2,
            y: destination.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func loadOrientedImage(at url: URL, sourceSize: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxPixels = Int(ceil(max(sourceSize.width, sourceSize.height)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
