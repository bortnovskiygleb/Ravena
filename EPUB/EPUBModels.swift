import Foundation

// MARK: - Core Models

struct EPUBBook {
    let title: String
    let author: String
    let language: String
    let chapters: [EPUBChapter]
    /// Raw cover image bytes, if the OPF declares one (either EPUB2's
    /// <meta name="cover"> or EPUB3's properties="cover-image"). nil for
    /// books with no declared cover.
    let coverImageData: Data?
    /// Independent of `chapters` — a single chapter file can hold several
    /// logical sections (e.g. "PILLOW-PROBLEMS." and "CHAPTER I." both
    /// living in the same physical file, a common real-world pattern), each
    /// its own entry pointing at a specific paragraph, not just the start of
    /// the chapter. Chapters with no real TOC entry pointing into them (a
    /// cover page, publisher boilerplate) simply have none here — see
    /// EPUBTOCEntry's own doc comment for how that's decided.
    let tableOfContents: [EPUBTOCEntry]
}

/// One entry in the book's table of contents — not one per chapter, since a
/// single chapter file can legitimately contain several of these (see
/// EPUBBook.tableOfContents).
struct EPUBTOCEntry: Identifiable {
    let id = UUID()
    let chapterIndex: Int
    /// Which paragraph within that chapter this entry targets — resolved
    /// from the nav/ncx entry's anchor fragment against the chapter's
    /// paragraphs' own anchorIDs (see EPUBParagraph). 0 (the chapter's very
    /// first paragraph) both for entries with no fragment and as the
    /// fallback when a fragment doesn't match anything found in the chapter
    /// — worst case, navigating there just lands on the chapter's first page
    /// instead of the exact spot, same as before this feature existed.
    let paragraphIndex: Int
    let title: String
    /// Nesting level from the source nav.xhtml/toc.ncx — 0 for a top-level
    /// entry (e.g. "Volume 1"), 1 for one nested inside it (e.g. "Chapter 1"
    /// within that volume), and so on. Heading-sniffed fallback entries
    /// (chapters with no real TOC entry) are always 0 — there's no
    /// hierarchy to infer for those.
    let depth: Int
}

struct EPUBChapter {
    let id: String
    var paragraphs: [EPUBParagraph]
}

struct EPUBParagraph: Identifiable {
    let id: UUID = UUID()
    let content: Content
    /// Style tag from the source HTML, kept simple for MVP rendering.
    /// Meaningless for .image paragraphs — kept on every paragraph anyway to
    /// avoid a second parallel model just for the text case.
    var style: ParagraphStyle
    /// Footnote body texts referenced within this paragraph's .text content,
    /// in the order their markers (see EPUBParagraph.footnoteMarker) appear
    /// in that text. Empty for the overwhelming majority of paragraphs, which
    /// have no footnotes.
    let footnotes: [String]
    /// HTML `id` attribute(s) associated with this paragraph — collected
    /// from the paragraph's own source element, its ancestors, and its
    /// descendants (an anchor can legitimately live at any of those relative
    /// to the actual heading/text a TOC entry means to target). Usually
    /// empty; used only to resolve a nav/ncx entry's `#fragment` to a
    /// specific paragraph — see EPUBParser.resolveAnchors.
    let anchorIDs: [String]

    enum Content {
        case text(String)
        /// Raw image bytes (JPEG/PNG/etc.), read from the EPUB archive at
        /// parse time — see EPUBParser.extractParagraphs. Loaded eagerly
        /// alongside the chapter's text rather than lazily on display;
        /// simple and consistent with how chapter text itself is already
        /// parsed eagerly, but it does mean a heavily-illustrated chapter's
        /// images all load into memory together when that chapter is first
        /// opened. Fine for typical books; worth revisiting for something
        /// like an image-heavy textbook or graphic novel.
        case image(Data)
    }

    /// A Private Use Area character standing in for "a footnote reference
    /// goes here" within a paragraph's raw text — never appears in real book
    /// text, so it's safe to use as an unambiguous split point. The Nth
    /// occurrence of this character in the text corresponds to
    /// `footnotes[N]`. ChapterRenderer replaces each occurrence with a
    /// visible superscript number when building the displayed attributed
    /// string — this marker itself is never shown to the user.
    static let footnoteMarker: Character = "\u{E000}"

    /// Convenience for call sites that only care about text and should
    /// simply skip image paragraphs (e.g. sniffing a chapter's first heading
    /// for its title) — nil for .image.
    var textContent: String? {
        if case .text(let value) = content { return value }
        return nil
    }
}

enum ParagraphStyle: Equatable {
    case heading1
    case heading2
    case body
    case italicBody
}

// MARK: - Internal manifest/spine models (used only during parsing)

struct OPFManifestItem {
    let id: String
    let href: String
    let mediaType: String
    /// Space-separated list of manifest properties, e.g. "nav" marks the
    /// EPUB3 navigation document. Optional since most items don't have any.
    let properties: String?
}

struct OPFDocument {
    let title: String
    let author: String
    let language: String
    let manifest: [String: OPFManifestItem] // keyed by id
    let spineItemIds: [String]              // reading order
    let basePath: String                    // folder containing the .opf file, relative to archive root
    /// Path (relative to archive root) to the EPUB3 navigation document
    /// (manifest item with properties="nav"), if the book has one.
    let navPath: String?
    /// Path (relative to archive root) to the EPUB2 NCX document
    /// (referenced by <spine toc="...">, or found by media-type as a
    /// fallback), if the book has one.
    let ncxPath: String?
    /// Path (relative to archive root) to the cover image, if the manifest
    /// declares one.
    let coverPath: String?
}
