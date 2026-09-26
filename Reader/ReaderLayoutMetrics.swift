import UIKit

enum ReaderLayoutMetrics {
    /// Must be used consistently everywhere a page's usable text area is
    /// measured or rendered (ChapterPaginator, ReaderPageViewController) — if
    /// pagination measures with one inset and rendering uses another, text
    /// will overflow or leave a visible gap at the page edge.
    static func textInsets(for settings: ReaderSettings) -> UIEdgeInsets {
        UIEdgeInsets(
            top: 16,
            left: CGFloat(settings.horizontalMargin),
            bottom: 48,
            right: CGFloat(settings.horizontalMargin)
        )
    }
}
