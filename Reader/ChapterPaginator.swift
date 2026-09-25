import UIKit

/// A single page's text plus where it begins within the chapter's full text —
/// the offset is what lets sentence extraction see past this page's own
/// boundaries into the rest of the chapter.
struct PaginatedPage {
    let text: NSAttributedString
    /// UTF-16 (NSString-compatible) character offset where this page begins
    /// within ChapterPagination.fullText.
    let startOffset: Int
}

struct ChapterPagination {
    let pages: [PaginatedPage]
    /// The whole chapter's plain text, in one piece — used to resolve a
    /// sentence that spans a page break, which a single page's text alone
    /// can't do.
    let fullText: String
    /// Character offset (UTF-16) where each of the chapter's paragraphs
    /// begins within fullText/the pages' combined text — used to find which
    /// page a TOC entry's target paragraph falls on.
    let paragraphStartOffsets: [Int]
}

enum ChapterPaginator {

    /// `pageSize` is the usable text area of one page — i.e. the page view's
    /// bounds minus ReaderLayoutMetrics.textInsets. Must match exactly what
    /// ReaderPageViewController applies as its textContainerInset, or text
    /// measured here won't be what actually fits there.
    static func paginate(
        chapter: EPUBChapter,
        settings: ReaderSettings,
        pageSize: CGSize
    ) -> ChapterPagination {
        let rendered = ChapterRenderer.render(chapter: chapter, settings: settings, maxImageWidth: pageSize.width)
        let fullAttributed = rendered.attributedString
        let fullText = fullAttributed.string

        guard pageSize.width > 0, pageSize.height > 0, fullAttributed.length > 0 else {
            return ChapterPagination(pages: [], fullText: fullText, paragraphStartOffsets: rendered.paragraphStartOffsets)
        }

        let textStorage = NSTextStorage(attributedString: fullAttributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var pages: [PaginatedPage] = []
        var consumedGlyphs = 0

        while consumedGlyphs < layoutManager.numberOfGlyphs {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)

            var glyphRange = layoutManager.glyphRange(for: container)

            if glyphRange.length == 0 {
                // Not even one line fit at the normal page size — most likely
                // an iPad Split View sliver combined with a large margin/line
                // spacing, or (rarer) a single unbroken word/URL wider than
                // the container. The settings sliders keep this practically
                // unreachable on their own (see ReaderSettings.Range), but
                // this is the actual guarantee: grow this one container until
                // something fits, rather than silently dropping the rest of
                // the chapter. The resulting page may look oversized, but no
                // text is lost.
                container.size = CGSize(width: pageSize.width, height: pageSize.height * 4)
                glyphRange = layoutManager.glyphRange(for: container)
                guard glyphRange.length > 0 else { break } // pageSize.width itself is unusable (e.g. 0) — nothing more we can do
            }

            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let pageAttributedText = NSMutableAttributedString(attributedString: fullAttributed.attributedSubstring(from: charRange))

            if charRange.location > 0 {
                let fullNSString = fullText as NSString
                let prevChar = fullNSString.substring(with: NSRange(location: charRange.location - 1, length: 1))
                if prevChar != "\n" {
                    let pageNSString = pageAttributedText.string as NSString
                    if pageNSString.length > 0 {
                        let firstParaRange = pageNSString.paragraphRange(for: NSRange(location: 0, length: 0))
                        pageAttributedText.enumerateAttribute(.paragraphStyle, in: firstParaRange, options: []) { value, range, _ in
                            if let style = value as? NSParagraphStyle {
                                let newStyle = style.mutableCopy() as! NSMutableParagraphStyle
                                newStyle.firstLineHeadIndent = newStyle.headIndent
                                pageAttributedText.addAttribute(.paragraphStyle, value: newStyle, range: range)
                            }
                        }
                    }
                }
            }

            pages.append(PaginatedPage(
                text: pageAttributedText,
                startOffset: charRange.location
            ))

            consumedGlyphs = NSMaxRange(glyphRange)
        }

        // Fallback: pagination failed for some reason (e.g. pageSize edge case) —
        // show the whole chapter as one (probably-overflowing) page rather than nothing.
        let resultPages = pages.isEmpty ? [PaginatedPage(text: fullAttributed, startOffset: 0)] : pages
        return ChapterPagination(pages: resultPages, fullText: fullText, paragraphStartOffsets: rendered.paragraphStartOffsets)
    }
}
