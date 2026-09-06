import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum DocumentLoader {
    public static func load(urls: [URL]) -> LoadResult {
        var pages: [InputPage] = []
        var skipped: [String] = []

        for url in sorted(urls: urls) {
            let normalizedURL = url.standardizedFileURL

            if isPDF(normalizedURL) {
                guard let document = PDFDocument(url: normalizedURL), document.pageCount > 0 else {
                    skipped.append(normalizedURL.lastPathComponent)
                    continue
                }

                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    let thumbnail = page.thumbnail(
                        of: thumbnailSize(for: bounds.size),
                        for: .mediaBox
                    )
                    let suffix = document.pageCount > 1 ? " · стр. \(index + 1)" : ""
                    pages.append(
                        InputPage(
                            sourceURL: normalizedURL,
                            sourcePageIndex: index,
                            displayName: normalizedURL.lastPathComponent + suffix,
                            imageSize: bounds.size,
                            thumbnail: thumbnail
                        )
                    )
                }
                continue
            }

            guard let loadedImage = loadImage(at: normalizedURL) else {
                skipped.append(normalizedURL.lastPathComponent)
                continue
            }

            pages.append(
                InputPage(
                    sourceURL: normalizedURL,
                    displayName: normalizedURL.lastPathComponent,
                    imageSize: loadedImage.size,
                    thumbnail: loadedImage.thumbnail
                )
            )
        }

        return LoadResult(pages: pages, skippedFileNames: skipped)
    }

    public static func sorted(urls: [URL]) -> [URL] {
        urls
            .map(\.standardizedFileURL)
            .filter { !$0.hasDirectoryPath }
            .sorted { lhs, rhs in
                let comparison = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent)
                if comparison == .orderedSame {
                    return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                }
                return comparison == .orderedAscending
            }
    }

    public static func recommendedFormat(for pages: [InputPage]) -> PageFormat {
        guard !pages.isEmpty else { return .a4 }

        let a4Ratio = 210.0 / 297.0
        let a4LikeCount = pages.reduce(into: 0) { result, page in
            let width = Double(page.imageSize.width)
            let height = Double(page.imageSize.height)
            guard width > 0, height > 0 else { return }
            let ratio = min(width, height) / max(width, height)
            if abs(ratio - a4Ratio) <= 0.045 {
                result += 1
            }
        }

        return Double(a4LikeCount) / Double(pages.count) >= 0.8 ? .a4 : .automatic
    }

    private static func isPDF(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return true }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
    }

    private static func loadImage(at url: URL) -> (size: CGSize, thumbnail: NSImage)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              pixelWidth > 0,
              pixelHeight > 0 else { return nil }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotatesQuarterTurn = [5, 6, 7, 8].contains(orientation)
        let displaySize = rotatesQuarterTurn
            ? CGSize(width: pixelHeight, height: pixelWidth)
            : CGSize(width: pixelWidth, height: pixelHeight)
        let pointSize = thumbnailSize(for: displaySize)
        let maxPixels = max(pointSize.width, pointSize.height) * 2
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(ceil(maxPixels)),
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return (
            displaySize,
            NSImage(cgImage: thumbnail, size: pointSize)
        )
    }

    private static func thumbnailSize(for sourceSize: CGSize) -> CGSize {
        let boundingSize = CGSize(width: 96, height: 112)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return boundingSize }
        let scale = min(boundingSize.width / sourceSize.width, boundingSize.height / sourceSize.height)
        return CGSize(width: max(1, sourceSize.width * scale), height: max(1, sourceSize.height * scale))
    }
}
