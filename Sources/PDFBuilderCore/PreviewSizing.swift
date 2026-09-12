import Foundation

public enum PreviewSizing {
    public static let defaultWidth: CGFloat = 52
    public static let maximumWidth: CGFloat = 320

    public static func clampedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return defaultWidth }
        return min(maximumWidth, max(defaultWidth, width))
    }

    public static func size(forWidth width: CGFloat) -> CGSize {
        let width = clampedWidth(width)
        return CGSize(width: width, height: width * 64 / 52)
    }
}
