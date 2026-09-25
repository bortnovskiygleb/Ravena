import UIKit

extension NSAttributedString.Key {
    /// Carries a footnote's body text on the small superscript marker
    /// ChapterRenderer inserts in place of EPUBParagraph.footnoteMarker —
    /// ReaderPageViewController checks for this attribute at the tap
    /// location to distinguish "user tapped a footnote" from a normal word tap.
    static let footnoteText = NSAttributedString.Key("readerapp.footnoteText")
}

enum ChapterRenderer {
    struct Result {
        let attributedString: NSAttributedString
        /// Character offset (UTF-16) where each of `chapter.paragraphs`
        /// begins within `attributedString` — parallel array, same count and
        /// order as chapter.paragraphs. Used to find which page a TOC
        /// entry's target paragraph ends up on after pagination.
        let paragraphStartOffsets: [Int]
    }

    /// Builds the full styled text for a chapter — one continuous attributed
    /// string, no page breaks. ChapterPaginator slices this into pages.
    ///
    /// `maxImageWidth` is the page's usable content width — images are scaled
    /// down to fit within it (preserving aspect ratio) so a photo-resolution
    /// illustration doesn't overflow a page horizontally. Pass the same value
    /// ChapterPaginator uses as its pageSize.width.
    static func render(chapter: EPUBChapter, settings: ReaderSettings, maxImageWidth: CGFloat) -> Result {
        let textColor = settings.backgroundTheme.textColor
        let attributed = NSMutableAttributedString()
        var paragraphStartOffsets: [Int] = []
        // Tracks the previous *text* paragraph's style so consecutive body
        // paragraphs can be told apart from "first body paragraph after a
        // heading/image" — only the former gets the no-blank-line/indented
        // treatment (items 6/7); a paragraph opening a new section
        // conventionally isn't indented in book typesetting.
        var previousStyle: ParagraphStyle?

        for paragraph in chapter.paragraphs {
            paragraphStartOffsets.append(attributed.length)

            switch paragraph.content {
            case .text(let text):
                let font: UIFont
                let paragraphStyle = NSMutableParagraphStyle() // fresh per paragraph — see note above
                paragraphStyle.lineSpacing = CGFloat(settings.lineSpacing)

                let isConsecutiveBodyParagraph = paragraph.style == .body && previousStyle == .body

                switch paragraph.style {
                case .heading1:
                    font = settings.fontStyle.font(ofSize: CGFloat(settings.fontSize) + 24, weight: .bold)
                    paragraphStyle.paragraphSpacingBefore = 28
                    paragraphStyle.paragraphSpacing = 6
                    let leftIndent = CGFloat(settings.fontSize) * 2.0
                    paragraphStyle.firstLineHeadIndent = leftIndent
                    paragraphStyle.headIndent = leftIndent
                case .heading2:
                    font = settings.fontStyle.font(ofSize: CGFloat(settings.fontSize) + 16, weight: .bold)
                    paragraphStyle.paragraphSpacingBefore = 20
                    paragraphStyle.paragraphSpacing = 4
                    let leftIndent = CGFloat(settings.fontSize) * 1.5
                    paragraphStyle.firstLineHeadIndent = leftIndent
                    paragraphStyle.headIndent = leftIndent
                case .italicBody:
                    font = settings.fontStyle.font(ofSize: CGFloat(settings.fontSize), italic: true)
                case .body:
                    font = settings.fontStyle.font(ofSize: CGFloat(settings.fontSize))
                    // Classic book-paragraph indent (~1.5em)
                    paragraphStyle.firstLineHeadIndent = CGFloat(settings.fontSize) * 1.5
                }

                let baseAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle,
                ]

                let separator = paragraph.style == .body ? "\n" : "\n\n"
                let piece = paragraph.footnotes.isEmpty
                    ? NSAttributedString(string: text + separator, attributes: baseAttributes)
                    : attributedStringSplittingFootnoteMarkers(
                        text: text + separator, footnotes: paragraph.footnotes,
                        baseFont: font, baseAttributes: baseAttributes
                    )
                attributed.append(piece)
                previousStyle = paragraph.style

            case .image(let data):
                // Corrupt or unsupported image data — skip it rather than
                // dropping the rest of the chapter over one bad picture.
                guard let image = UIImage(data: data), image.size.width > 0 else { continue }

                let attachment = NSTextAttachment()
                attachment.image = image

                // NSTextAttachment defaults to the image's native pixel size,
                // which for anything above a low-res illustration would badly
                // overflow the page width. Scale down (never up — a small
                // image shouldn't get blurrily stretched) to fit, preserving
                // aspect ratio; TextKit lays out the resulting height as part
                // of normal pagination, same as any line of text, including
                // falling through to ChapterPaginator's own overflow handling
                // if a very tall image still doesn't fit on one page.
                let scale = min(maxImageWidth / image.size.width, 1)
                let displaySize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                attachment.bounds = CGRect(origin: .zero, size: displaySize)

                let imageParagraphStyle = NSMutableParagraphStyle()
                imageParagraphStyle.lineSpacing = CGFloat(settings.lineSpacing)
                let imagePiece = NSMutableAttributedString(attachment: attachment)
                imagePiece.append(NSAttributedString(string: "\n\n", attributes: [.paragraphStyle: imageParagraphStyle]))
                attributed.append(imagePiece)
                previousStyle = nil // an image is a visual break, same as a heading — the next body paragraph shouldn't be treated as "consecutive"
            }
        }

        return Result(attributedString: attributed, paragraphStartOffsets: paragraphStartOffsets)
    }

    /// Splits `text` around each EPUBParagraph.footnoteMarker occurrence,
    /// replacing it with a small superscript number that carries the
    /// corresponding footnote body via the .footnoteText attribute. Built by
    /// scanning for marker occurrences rather than iterating character-by-
    /// character, so this stays cheap even for a long paragraph with only
    /// one or two footnotes.
    private static func attributedStringSplittingFootnoteMarkers(
        text: String,
        footnotes: [String],
        baseFont: UIFont,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = Substring(text)
        var footnoteIndex = 0

        while let markerRange = remaining.range(of: String(EPUBParagraph.footnoteMarker)) {
            let before = String(remaining[remaining.startIndex..<markerRange.lowerBound])
            if !before.isEmpty {
                result.append(NSAttributedString(string: before, attributes: baseAttributes))
            }

            footnoteIndex += 1
            if footnoteIndex <= footnotes.count {
                var markerAttributes = baseAttributes
                markerAttributes[.font] = baseFont.withSize(baseFont.pointSize * 0.7)
                markerAttributes[.foregroundColor] = UIColor.systemBlue
                markerAttributes[.baselineOffset] = baseFont.pointSize * 0.3
                markerAttributes[.footnoteText] = footnotes[footnoteIndex - 1]
                result.append(NSAttributedString(string: superscriptLabel(footnoteIndex), attributes: markerAttributes))
            }
            // If footnoteIndex somehow exceeds footnotes.count (shouldn't
            // happen — parser only ever inserts a marker alongside a matching
            // append to the footnotes array — but if it did, the marker
            // character is just dropped rather than shown literally).

            remaining = remaining[markerRange.upperBound...]
        }

        if !remaining.isEmpty {
            result.append(NSAttributedString(string: String(remaining), attributes: baseAttributes))
        }

        return result
    }

    private static func superscriptLabel(_ number: Int) -> String {
        let superscriptDigits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        ]
        return String(String(number).compactMap { superscriptDigits[$0] })
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
