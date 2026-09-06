import AppKit
import Foundation

public struct InputPage: Identifiable {
    public let id: UUID
    public let sourceURL: URL
    public let sourcePageIndex: Int?
    public let displayName: String
    public let imageSize: CGSize
    public let thumbnail: NSImage

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourcePageIndex: Int? = nil,
        displayName: String,
        imageSize: CGSize,
        thumbnail: NSImage
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourcePageIndex = sourcePageIndex
        self.displayName = displayName
        self.imageSize = imageSize
        self.thumbnail = thumbnail
    }
}

public enum PageFormat: String, CaseIterable, Identifiable {
    case a4
    case automatic

    public var id: Self { self }

    public var title: String {
        switch self {
        case .a4: "A4"
        case .automatic: "Авто"
        }
    }
}

public struct LoadResult {
    public let pages: [InputPage]
    public let skippedFileNames: [String]

    public init(pages: [InputPage], skippedFileNames: [String]) {
        self.pages = pages
        self.skippedFileNames = skippedFileNames
    }
}
