import Foundation
import ZIPFoundation   // SPM: https://github.com/weichsel/ZIPFoundation
import SwiftSoup       // SPM: https://github.com/scinfu/SwiftSoup

enum EPUBParserError: Error {
    case invalidArchive
    case containerNotFound
    case opfNotFound
    case malformedXML(String)
}

/// A raw table-of-contents entry as found in nav.xhtml/toc.ncx, before
/// resolution against actual chapters — see EPUBParser.resolveTableOfContents.
private struct TOCSourceEntry {
    let path: String
    let fragment: String?
    let title: String
    /// Nesting level in the source nav.xhtml/toc.ncx — 0 for top-level.
    let depth: Int
}

final class EPUBParser {

    /// Parses an .epub file at the given URL into an EPUBBook.
    func parse(fileURL: URL) throws -> EPUBBook {
        guard let archive = Archive(url: fileURL, accessMode: .read) else {
            throw EPUBParserError.invalidArchive
        }

        // 1. Read META-INF/container.xml to find the .opf path
        let opfPath = try readOPFPath(from: archive)

        // 2. Read and parse the .opf manifest + spine
        let opfXML = try readEntry(path: opfPath, from: archive)
        let opf = try parseOPF(xmlString: opfXML, opfPath: opfPath)

        // 2b. Raw table-of-contents entries (EPUB3 nav.xhtml, or EPUB2
        // toc.ncx as a fallback) — file path + optional #fragment + title,
        // not yet resolved to a chapter/paragraph since that needs the
        // chapters to be parsed first (see resolveTableOfContents below).
        let tocSourceEntries = tableOfContentsSourceEntries(opf: opf, archive: archive)

        // 2c. Cover image, if the manifest declares one. Best-effort — a
        // missing or unreadable cover just means coverImageData is nil, not
        // a failed import.
        let coverImageData = opf.coverPath.flatMap { try? readBinaryEntry(path: $0, from: archive) }

        // 2d. Cache for cross-file footnote lookups (e.g. a book-wide
        // "notes.xhtml" referenced by many chapters) — declared here, at book
        // scope, and threaded through to every chapter's extractParagraphs
        // call, so such a file is parsed once for the whole book rather than
        // once per chapter that happens to reference it.
        var footnoteDocumentCache: [String: SwiftSoup.Document] = [:]

        // 3. Walk the spine in order, extract each chapter's text
        var chapters: [EPUBChapter] = []
        var chapterPaths: [String] = [] // parallel to `chapters`; used to resolve TOC entries below
        for itemId in opf.spineItemIds {
            guard let item = opf.manifest[itemId] else { continue }
            let chapterPath = resolvePath(href: item.href, relativeTo: opf.basePath)
            let chapterDirectory = (chapterPath as NSString).deletingLastPathComponent
            let html = try readEntry(path: chapterPath, from: archive)
            let paragraphs = try extractParagraphs(
                fromHTML: html, archive: archive, chapterDirectory: chapterDirectory,
                footnoteDocumentCache: &footnoteDocumentCache
            )

            chapters.append(EPUBChapter(id: itemId, paragraphs: paragraphs))
            chapterPaths.append(chapterPath)
        }

        // 4. Now that every chapter's paragraphs (and their anchorIDs) are
        // known, resolve the raw TOC entries against them.
        let tableOfContents = resolveTableOfContents(
            sourceEntries: tocSourceEntries, chapters: chapters, chapterPaths: chapterPaths
        )

        // 5. Upgrade paragraph styles for TOC targets — any paragraph a TOC
        // entry points to is logically a chapter/section heading, regardless
        // of what HTML tag the author originally used for it.
        for entry in tableOfContents {
            let chapIdx = entry.chapterIndex
            let paraIdx = entry.paragraphIndex
            if chapters.indices.contains(chapIdx) && chapters[chapIdx].paragraphs.indices.contains(paraIdx) {
                if chapters[chapIdx].paragraphs[paraIdx].textContent != nil {
                    chapters[chapIdx].paragraphs[paraIdx].style = entry.depth == 0 ? .heading1 : .heading2
                }
            }
        }

        return EPUBBook(
            title: opf.title,
            author: opf.author,
            language: opf.language,
            chapters: chapters,
            coverImageData: coverImageData,
            tableOfContents: tableOfContents
        )
    }

    /// Resolves each raw TOC entry (file path + optional fragment) to a
    /// concrete (chapterIndex, paragraphIndex) using the chapters' own
    /// paragraphs and their anchorIDs. A chapter with zero resolved entries
    /// gets one synthesized from its first heading, if it has one; if not
    /// (a cover page, publisher boilerplate — content that was never meant
    /// to be a navigable "chapter"), it simply doesn't appear in the table
    /// of contents at all, the same way Apple Books' own reader handles it.
    private func resolveTableOfContents(
        sourceEntries: [TOCSourceEntry],
        chapters: [EPUBChapter],
        chapterPaths: [String]
    ) -> [EPUBTOCEntry] {
        var resolved: [EPUBTOCEntry] = []

        for source in sourceEntries {
            guard let chapterIndex = chapterPaths.firstIndex(of: source.path) else { continue }

            let paragraphIndex: Int
            if let fragment = source.fragment, !fragment.isEmpty,
               let matchIndex = chapters[chapterIndex].paragraphs.firstIndex(where: { $0.anchorIDs.contains(fragment) }) {
                // Found the exact paragraph this entry's anchor points to —
                // e.g. two different sections ("PILLOW-PROBLEMS." and
                // "CHAPTER I.") that happen to live in the same physical
                // file resolve to two different entries here, each jumping
                // to its own paragraph rather than both landing on the
                // file's first page.
                paragraphIndex = matchIndex
            } else {
                // No fragment, or one that doesn't match anything found in
                // the chapter — falls back to that chapter's first
                // paragraph, same as if this feature didn't exist.
                paragraphIndex = 0
            }
            resolved.append(EPUBTOCEntry(chapterIndex: chapterIndex, paragraphIndex: paragraphIndex, title: source.title, depth: source.depth))
        }

        let chaptersWithEntries = Set(resolved.map(\.chapterIndex))
        for (index, chapter) in chapters.enumerated() where !chaptersWithEntries.contains(index) {
            if let sniffedTitle = chapter.paragraphs.first(where: { $0.style == .heading1 || $0.style == .heading2 })?.textContent {
                resolved.append(EPUBTOCEntry(chapterIndex: index, paragraphIndex: 0, title: sniffedTitle, depth: 0))
            }
        }

        // Sort into reading order — sourceEntries is already roughly in
        // document order, but the heading-sniffed fallbacks were appended
        // afterwards out of order, and mixing books that use both sources
        // for different chapters could otherwise interleave oddly.
        return resolved.sorted { ($0.chapterIndex, $0.paragraphIndex) < ($1.chapterIndex, $1.paragraphIndex) }
    }

    // MARK: - Step 1: container.xml

    private func readOPFPath(from archive: Archive) throws -> String {
        let containerXML = try readEntry(path: "META-INF/container.xml", from: archive)

        // container.xml is small and predictable; a lightweight regex/XMLParser is enough,
        // no need for SwiftSoup here since this isn't HTML.
        let parser = XMLParser(data: Data(containerXML.utf8))
        let delegate = ContainerXMLDelegate()
        parser.delegate = delegate
        parser.parse()

        guard let path = delegate.fullPath else {
            throw EPUBParserError.containerNotFound
        }
        return path
    }

    // MARK: - Step 2: .opf manifest + spine

    private func parseOPF(xmlString: String, opfPath: String) throws -> OPFDocument {
        let parser = XMLParser(data: Data(xmlString.utf8))
        let delegate = OPFXMLDelegate()
        parser.delegate = delegate
        // Namespace-aware parsing is what lets OPFXMLDelegate match Dublin Core
        // elements (title/creator/language) by their actual namespace URI
        // rather than assuming every EPUB binds it to the "dc" prefix
        // specifically — see the delegate's doc comment for why that matters.
        parser.shouldProcessNamespaces = true
        parser.parse()

        let basePath = (opfPath as NSString).deletingLastPathComponent

        // EPUB3: the nav document is whichever manifest item is marked
        // properties="nav" (properties is a space-separated list, so a
        // straight equality check would miss "nav cover-image" etc.).
        let navItem = delegate.manifestItems.values.first {
            ($0.properties ?? "").split(separator: " ").contains("nav")
        }
        let navPath = navItem.map { resolvePath(href: $0.href, relativeTo: basePath) }

        // EPUB2: the NCX is whatever the spine's toc="..." attribute points
        // to by manifest id; if that's missing (some encoders omit it even
        // though the spec requires it), fall back to finding it by its
        // standard media-type.
        let ncxItem = delegate.spineTocId.flatMap { delegate.manifestItems[$0] }
            ?? delegate.manifestItems.values.first { $0.mediaType == "application/x-dtbncx+xml" }
        let ncxPath = ncxItem.map { resolvePath(href: $0.href, relativeTo: basePath) }

        // Cover image: EPUB3 marks it with properties="cover-image" directly
        // on the manifest item; EPUB2 has no such property and instead points
        // to it indirectly via <meta name="cover" content="manifest-item-id">
        // in <metadata>. Try EPUB3 first since it's unambiguous when present.
        let coverItem = delegate.manifestItems.values.first {
            ($0.properties ?? "").split(separator: " ").contains("cover-image")
        } ?? delegate.coverImageManifestID.flatMap { delegate.manifestItems[$0] }
        let coverPath = coverItem.map { resolvePath(href: $0.href, relativeTo: basePath) }

        return OPFDocument(
            title: delegate.title ?? "Untitled",
            author: delegate.author ?? "Unknown",
            language: delegate.language ?? "en",
            manifest: delegate.manifestItems,
            spineItemIds: delegate.spineItemIds,
            basePath: basePath,
            navPath: navPath,
            ncxPath: ncxPath,
            coverPath: coverPath
        )
    }

    // MARK: - Step 3: chapter HTML -> paragraphs

    private func extractParagraphs(
        fromHTML html: String,
        archive: Archive,
        chapterDirectory: String,
        footnoteDocumentCache: inout [String: SwiftSoup.Document]
    ) throws -> [EPUBParagraph] {
        let doc = try SwiftSoup.parse(html)
        guard let body = doc.body() else { return [] }

        var paragraphs: [EPUBParagraph] = []

        // Select the block-level elements we care about for MVP, plus img —
        // img is included in the same top-level select() (rather than
        // handled separately) so images come out interleaved with
        // surrounding text in document order, not all at the end.
        // h3/h4 included alongside h1/h2 — some EPUBs use deeper heading
        // levels for section titles within a chapter; without this their
        // text was silently dropped from the reading content entirely (not
        // just missing from the table of contents).
        // li included — list items are how many EPUBs mark up an in-book
        // "Contents" page (<ol><li><a>Chapter 1</a></li>...) or any bulleted/
        // numbered content; without it that content (links included) simply
        // never appeared at all, not even as plain text.
        let blocks = try body.select("p, h1, h2, h3, h4, blockquote, li, img")
        for element in blocks {
            // Footnote bodies (typically <aside epub:type="footnote">...) get
            // pulled in separately, inline at their reference point (see
            // resolveFootnoteText below) — without this check they'd *also*
            // show up here as their own orphaned paragraph, wherever in the
            // document the footnote container happens to sit (often the end
            // of the chapter), with no indication they're a footnote.
            if isInsideFootnoteContainer(element) { continue }

            if element.tagName() == "img" {
                guard let src = try? element.attr("src"), !src.isEmpty else { continue }
                let imagePath = resolvePath(href: src, relativeTo: chapterDirectory)
                // Missing/unreadable/oversized image: skip it rather than
                // failing the whole chapter over one bad picture.
                guard let imageData = try? readBinaryEntry(path: imagePath, from: archive) else { continue }
                paragraphs.append(EPUBParagraph(
                    content: .image(imageData), style: .body, footnotes: [],
                    anchorIDs: collectAnchorIDs(for: element)
                ))
                continue
            }

            let (text, footnotes) = extractTextAndFootnotes(
                from: element,
                currentDocument: doc,
                chapterDirectory: chapterDirectory,
                archive: archive,
                documentCache: &footnoteDocumentCache
            )
            guard !text.isEmpty else { continue }

            let style: ParagraphStyle
            switch element.tagName() {
            case "h1": style = .heading1
            case "h2", "h3", "h4": style = .heading2
            case "blockquote": style = .italicBody
            default: style = .body
            }

            paragraphs.append(EPUBParagraph(
                content: .text(text), style: style, footnotes: footnotes,
                anchorIDs: collectAnchorIDs(for: element)
            ))
        }

        return paragraphs
    }

    /// IDs a TOC entry's #fragment might be targeting: the element's own
    /// `id`, plus any descendant's (covers the common `<h2><a id="x"/>
    /// Chapter 1</h2>` pattern, an empty anchor nested just inside the
    /// heading it actually labels). Deliberately does *not* walk ancestors —
    /// a shared wrapper's id would then get attributed to every paragraph
    /// inside it, making resolution ambiguous rather than more accurate.
    private func collectAnchorIDs(for element: Element) -> [String] {
        var ids: [String] = []
        if let ownID = try? element.attr("id"), !ownID.isEmpty {
            ids.append(ownID)
        }
        if let idElements = try? element.select("[id]") {
            for idElement in idElements.array() {
                if let descendantID = try? idElement.attr("id"), !descendantID.isEmpty {
                    ids.append(descendantID)
                }
            }
        }
        return ids
    }

    // MARK: - Footnotes

    /// True if `element` (or any ancestor) is marked as footnote/endnote
    /// content per the EPUB3 structural semantics vocabulary — used to keep
    /// footnote bodies out of the normal reading flow (they're pulled in
    /// separately, inline at their reference point).
    private func isInsideFootnoteContainer(_ element: Element) -> Bool {
        var current = element.parent()
        while let node = current {
            if let epubType = try? node.attr("epub:type"),
               epubType.contains("footnote") || epubType.contains("rearnote") || epubType.contains("endnote") {
                return true
            }
            current = node.parent()
        }
        return false
    }

    /// Walks `element`'s content, collecting visible text normally but
    /// replacing each footnote reference (`epub:type="noteref"`) with
    /// EPUBParagraph.footnoteMarker instead of its own visible text (usually
    /// just a number) — the resolved footnote body is collected separately,
    /// in the order its marker appears.
    private func extractTextAndFootnotes(
        from element: Element,
        currentDocument: SwiftSoup.Document,
        chapterDirectory: String,
        archive: Archive,
        documentCache: inout [String: SwiftSoup.Document]
    ) -> (text: String, footnotes: [String]) {
        var text = ""
        var footnotes: [String] = []
        walkForFootnotes(
            element, text: &text, footnotes: &footnotes,
            currentDocument: currentDocument, chapterDirectory: chapterDirectory,
            archive: archive, documentCache: &documentCache
        )
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), footnotes)
    }

    /// Walks `element`'s content collecting visible text, with two kinds of
    /// inline element replaced by something better than their raw flattened
    /// text: a footnote reference becomes a marker (see extractTextAndFootnotes's
    /// doc comment), and a MathML formula becomes its publisher-provided
    /// plain-text fallback instead of being flattened character-by-character.
    private func walkForFootnotes(
        _ node: Node,
        text: inout String,
        footnotes: inout [String],
        currentDocument: SwiftSoup.Document,
        chapterDirectory: String,
        archive: Archive,
        documentCache: inout [String: SwiftSoup.Document]
    ) {
        if let element = node as? Element {
            let epubType = (try? element.attr("epub:type")) ?? ""
            if epubType.contains("noteref"), let href = try? element.attr("href"), !href.isEmpty {
                if let footnoteText = resolveFootnoteText(
                    href: href, currentDocument: currentDocument, chapterDirectory: chapterDirectory,
                    archive: archive, documentCache: &documentCache
                ) {
                    footnotes.append(footnoteText)
                    text.append(EPUBParagraph.footnoteMarker)
                    return // don't also descend into the reference's own visible text (usually just a number)
                }
                // Couldn't resolve the target (broken link, unreadable file) —
                // fall through and include its visible text normally, so at
                // least the marker number isn't silently lost.
            }

            if element.tagName() == "math" {
                // MathML's own text content — individual variable letters,
                // digits, operators, each their own element — has no
                // separators between them when flattened naively, producing
                // unreadable soup (e.g. "x2y2r2" for x²+y²=r²). Publishers
                // commonly include a plain-text or TeX fallback specifically
                // for readers that can't render MathML — prefer that; if
                // there isn't one, drop the formula rather than show garbled
                // text, since that's actively misleading rather than merely
                // incomplete.
                if let fallback = mathFallbackText(for: element) {
                    text.append(" [")
                    text.append(fallback)
                    text.append("] ")
                }
                return // never descend into raw MathML markup
            }

            for child in element.getChildNodes() {
                walkForFootnotes(
                    child, text: &text, footnotes: &footnotes,
                    currentDocument: currentDocument, chapterDirectory: chapterDirectory,
                    archive: archive, documentCache: &documentCache
                )
            }
        } else if let textNode = node as? TextNode {
            text.append(textNode.text())
        }
    }

    /// Looks for a plain-text (or TeX) fallback a publisher included in a
    /// MathML formula for readers that can't render MathML itself — checked
    /// in the order a reader is most likely to find one:
    /// 1. The `alttext` attribute directly on `<math>` (simple, common).
    /// 2. An `<annotation>` child (used inside `<semantics>`, typically
    ///    holding the original TeX/AsciiMath source the formula was authored in).
    /// Returns nil if neither is present — callers should drop the formula
    /// rather than fall back to flattening the raw MathML markup.
    private func mathFallbackText(for mathElement: Element) -> String? {
        if let alttext = try? mathElement.attr("alttext"), !alttext.isEmpty {
            return alttext
        }
        if let annotation = (try? mathElement.select("annotation"))?.array().first,
           let annotationText = try? annotation.text().trimmingCharacters(in: .whitespacesAndNewlines),
           !annotationText.isEmpty {
            return annotationText
        }
        return nil
    }

    /// Resolves a noteref's `href` (e.g. "#fn1" for a same-document footnote,
    /// or "notes.xhtml#fn1" for one shared across the book) to the target
    /// element's flattened text.
    private func resolveFootnoteText(
        href: String,
        currentDocument: SwiftSoup.Document,
        chapterDirectory: String,
        archive: Archive,
        documentCache: inout [String: SwiftSoup.Document]
    ) -> String? {
        // omittingEmptySubsequences: false matters here — "#fn1" (the common
        // same-document case) has an *empty* file part before the "#", which
        // the default (true) would silently drop, leaving only one element
        // and making every same-document footnote fail to resolve.
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil } // no fragment — nothing to look up
        let filePart = String(parts[0])
        let fragmentID = String(parts[1])

        let targetDocument: SwiftSoup.Document
        if filePart.isEmpty {
            targetDocument = currentDocument
        } else {
            let resolvedPath = resolvePath(href: filePart, relativeTo: chapterDirectory)
            if let cached = documentCache[resolvedPath] {
                targetDocument = cached
            } else {
                guard let html = try? readEntry(path: resolvedPath, from: archive),
                      let parsed = try? SwiftSoup.parse(html) else { return nil }
                documentCache[resolvedPath] = parsed
                targetDocument = parsed
            }
        }

        guard let targetElement = try? targetDocument.getElementById(fragmentID) else { return nil }
        let flattened = (try? targetElement.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        return flattened.isEmpty ? nil : flattened
    }

    private func tableOfContentsSourceEntries(opf: OPFDocument, archive: Archive) -> [TOCSourceEntry] {
        if let navPath = opf.navPath, let html = try? readEntry(path: navPath, from: archive) {
            let navDirectory = (navPath as NSString).deletingLastPathComponent
            let entries = tocEntriesFromNav(html: html, navDirectory: navDirectory)
            if !entries.isEmpty { return entries }
        }
        if let ncxPath = opf.ncxPath, let xml = try? readEntry(path: ncxPath, from: archive) {
            let ncxDirectory = (ncxPath as NSString).deletingLastPathComponent
            let entries = tocEntriesFromNCX(xml: xml, ncxDirectory: ncxDirectory)
            if !entries.isEmpty { return entries }
        }
        return []
    }

    /// EPUB3: the nav document is itself XHTML, with the TOC being a
    /// `<nav>` element containing a nested list of `<a href="...">Title</a>`.
    /// Every link becomes its own entry — unlike the old one-title-per-file
    /// model, two links pointing at different anchors within the *same*
    /// file (a common pattern — several logical sections sharing one
    /// physical chapter file) now both survive instead of one silently
    /// overwriting the other.
    private func tocEntriesFromNav(html: String, navDirectory: String) -> [TOCSourceEntry] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }
        let navElements = ((try? doc.select("nav"))?.array()) ?? []

        // A nav document can contain more than one <nav> (toc, landmarks,
        // page-list) — prefer the one explicitly marked as the table of
        // contents; fall back to the first <nav> if none is marked (some
        // simpler export tools omit epub:type).
        let tocNav = navElements.first { element in
            (try? element.attr("epub:type"))?.contains("toc") == true
        } ?? navElements.first

        guard let tocNav else { return [] }

        // The TOC's hierarchy is nested <ol>/<li> — a <li> containing its
        // own nested <ol> means "this entry has sub-entries". Walk it
        // recursively instead of a flat select("a"), which would flatten
        // every level into one and lose the volume/chapter structure entirely.
        guard let topList = ((try? tocNav.select("> ol"))?.array().first)
            ?? ((try? tocNav.select("ol"))?.array().first) else { return [] }

        var results: [TOCSourceEntry] = []
        walkNavList(topList, depth: 0, navDirectory: navDirectory, results: &results)
        return results
    }

    private func walkNavList(_ list: Element, depth: Int, navDirectory: String, results: inout [TOCSourceEntry]) {
        let items = ((try? list.select("> li"))?.array()) ?? []
        for item in items {
            if let link = ((try? item.select("> a"))?.array().first),
               let href = try? link.attr("href"), !href.isEmpty,
               let text = try? link.text().trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                let (path, fragment) = resolvePathWithFragment(href: href, relativeTo: navDirectory)
                results.append(TOCSourceEntry(path: path, fragment: fragment, title: text, depth: depth))
            }
            // A nested <ol> directly inside this <li> is this entry's own
            // sub-list — recurse one level deeper.
            if let nestedList = ((try? item.select("> ol"))?.array().first) {
                walkNavList(nestedList, depth: depth + 1, navDirectory: navDirectory, results: &results)
            }
        }
    }

    /// EPUB2: the NCX is XML with `<navPoint><navLabel><text>Title</text>
    /// </navLabel><content src="..."/></navPoint>` entries (possibly
    /// nested) — same "every entry survives" reasoning as tocEntriesFromNav.
    private func tocEntriesFromNCX(xml: String, ncxDirectory: String) -> [TOCSourceEntry] {
        let parser = XMLParser(data: Data(xml.utf8))
        let delegate = NCXXMLDelegate()
        parser.delegate = delegate
        parser.parse()

        return delegate.entries.map { entry in
            let (path, fragment) = resolvePathWithFragment(href: entry.contentSrc, relativeTo: ncxDirectory)
            return TOCSourceEntry(path: path, fragment: fragment, title: entry.title, depth: entry.depth)
        }
    }

    // MARK: - Path resolution

    /// Resolves `href` (possibly with a `#fragment` and `./`/`../` segments)
    /// against `baseDirectory` (a path relative to the archive root), and
    /// strips the fragment — producing a normalized path that can be
    /// reliably string-compared against a spine chapter's own resolved path,
    /// regardless of which directory either one was originally written
    /// relative to.
    private func resolvePath(href: String, relativeTo baseDirectory: String) -> String {
        let withoutFragment = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        let combined = baseDirectory.isEmpty ? withoutFragment : "\(baseDirectory)/\(withoutFragment)"

        var components: [String] = []
        for part in combined.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                if !components.isEmpty { components.removeLast() }
                continue
            }
            components.append(String(part))
        }
        return components.joined(separator: "/")
    }

    /// Like resolvePath, but also returns the fragment — needed for TOC
    /// entries specifically, where the fragment identifies *which paragraph*
    /// within the target file to jump to, not just which file it is.
    private func resolvePathWithFragment(href: String, relativeTo baseDirectory: String) -> (path: String, fragment: String?) {
        // omittingEmptySubsequences: false matters here for the same reason
        // it does in resolveFootnoteText — "#fn1" alone (empty file part)
        // would otherwise collapse to one element instead of two.
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let filePart = String(parts[0])
        let fragment = parts.count == 2 ? String(parts[1]) : nil
        return (resolvePath(href: filePart, relativeTo: baseDirectory), fragment)
    }

    // MARK: - Helpers

    /// Extracts a single entry from the ZIP archive as a UTF-8 string.
    private func readEntry(path: String, from archive: Archive) throws -> String {
        guard let entry = archive[path] else {
            throw EPUBParserError.malformedXML("Entry not found: \(path)")
        }

        // Defends against a malicious or corrupt EPUB whose entry decompresses
        // to something enormous (a "zip bomb") — container.xml/.opf/chapter
        // XHTML files are text and realistically never anywhere near this size.
        let maxUncompressedSize: UInt64 = 20 * 1024 * 1024 // 20 MB
        guard UInt64(entry.uncompressedSize) <= maxUncompressedSize else {
            throw EPUBParserError.malformedXML("Entry too large: \(path)")
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw EPUBParserError.malformedXML("Non-UTF8 entry: \(path)")
        }
        return string
    }

    /// Like readEntry, but returns raw bytes instead of decoding as UTF-8
    /// text — for binary content (images), not XML/HTML.
    private func readBinaryEntry(path: String, from archive: Archive) throws -> Data {
        guard let entry = archive[path] else {
            throw EPUBParserError.malformedXML("Entry not found: \(path)")
        }

        // Same zip-bomb defense as readEntry, with more headroom — a
        // legitimate illustration can reasonably be a few MB, unlike a
        // chapter's XHTML.
        let maxUncompressedSize: UInt64 = 15 * 1024 * 1024 // 15 MB
        guard UInt64(entry.uncompressedSize) <= maxUncompressedSize else {
            throw EPUBParserError.malformedXML("Image too large: \(path)")
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }
}

// MARK: - XMLParser delegates (lightweight, no external XML dependency needed)

/// Extracts the full-path attribute of <rootfile> from META-INF/container.xml
private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var fullPath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile" {
            fullPath = attributeDict["full-path"]
        }
    }
}

/// Parses the .opf file: metadata, manifest items, spine order.
///
/// Requires the XMLParser using this delegate to have
/// `shouldProcessNamespaces = true` set — that's what makes `namespaceURI`
/// below resolved and reliable, rather than assuming Dublin Core elements are
/// always written with a literal "dc:" prefix (a near-universal convention,
/// but not one the OPF spec actually requires; what's required is binding the
/// prefix to the Dublin Core Elements 1.1 namespace URI, which is what we
/// match against here instead).
private final class OPFXMLDelegate: NSObject, XMLParserDelegate {
    var title: String?
    var author: String?
    var language: String?
    var manifestItems: [String: OPFManifestItem] = [:]
    var spineItemIds: [String] = []
    /// The manifest item id the <spine toc="..."> attribute points to, if present.
    var spineTocId: String?
    /// The manifest item id from EPUB2-style <meta name="cover" content="...">.
    var coverImageManifestID: String?

    private var currentText = ""
    private var isInsideDublinCoreElement = false

    private let dublinCoreNamespace = "http://purl.org/dc/elements/1.1/"

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentText = ""

        switch elementName {
        case "item":
            guard let id = attributeDict["id"], let href = attributeDict["href"] else { return }
            let mediaType = attributeDict["media-type"] ?? ""
            manifestItems[id] = OPFManifestItem(
                id: id, href: href, mediaType: mediaType, properties: attributeDict["properties"]
            )
        case "itemref":
            if let idref = attributeDict["idref"] {
                spineItemIds.append(idref)
            }
        case "spine":
            spineTocId = attributeDict["toc"]
        case "meta":
            if attributeDict["name"] == "cover", let content = attributeDict["content"] {
                coverImageManifestID = content
            }
        case "title", "creator", "language":
            // With namespace processing on, `elementName` is already the local
            // name (no prefix) regardless of what prefix the document used —
            // the actual check for "is this really Dublin Core" is the URI.
            isInsideDublinCoreElement = (namespaceURI == dublinCoreNamespace)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer { isInsideDublinCoreElement = false }

        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isInsideDublinCoreElement, !trimmed.isEmpty else { return }

        switch elementName {
        case "title":
            if title == nil { title = trimmed }
        case "creator":
            if author == nil { author = trimmed }
        case "language":
            if language == nil { language = trimmed }
        default:
            break
        }
    }
}

/// Parses toc.ncx (EPUB2's table-of-contents format): a tree of <navPoint>
/// elements, each with a <navLabel><text> (the title) followed by a
/// <content src="..."/> (the target file). Nesting is ignored — we just
/// collect every (title, contentSrc) pair in document order, which is enough
/// to map each spine chapter to its title regardless of TOC hierarchy depth.
private final class NCXXMLDelegate: NSObject, XMLParserDelegate {
    struct Entry {
        let title: String
        let contentSrc: String
        /// Nesting level of the <navPoint> this came from — 0 for a
        /// top-level entry, 1 for one nested inside it, and so on.
        let depth: Int
    }

    var entries: [Entry] = []

    private var currentText = ""
    private var isInsideNavLabelText = false
    /// Set when a <navLabel><text> finishes, consumed by the <content> that
    /// follows it within the same <navPoint> (that ordering — label before
    /// content — is fixed by the NCX schema).
    private var pendingTitle: String?
    /// <pageList>'s <pageTarget> entries use the *identical* structure as a
    /// real chapter's <navPoint> — <navLabel><text>...</text></navLabel>
    /// <content src="..."/> — just for page numbers ("[Pg 53]") instead of
    /// chapter titles. Without tracking whether we're actually inside
    /// <navMap>, those page-number entries got mistaken for chapter titles,
    /// which could — for whichever chapter happened to have no real navMap
    /// entry — silently replace a sensible fallback with a bare page number.
    private var isInsideNavMap = false
    /// How many <navPoint> elements deep we currently are — <navPoint> can
    /// nest arbitrarily (a volume containing chapters, which is exactly the
    /// case the table-of-contents tree view needs to represent).
    private var navPointDepth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "navMap":
            isInsideNavMap = true
        case "navPoint":
            if isInsideNavMap { navPointDepth += 1 }
        case "text":
            currentText = ""
            isInsideNavLabelText = true
        case "content":
            guard isInsideNavMap else { return } // ignore pageList's <content>
            if let title = pendingTitle, let src = attributeDict["src"] {
                // navPointDepth was already incremented on entering this
                // navPoint, so subtract 1 to make the outermost level 0.
                entries.append(Entry(title: title, contentSrc: src, depth: max(navPointDepth - 1, 0)))
                pendingTitle = nil
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideNavLabelText {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "navMap" {
            isInsideNavMap = false
            return
        }
        if elementName == "navPoint" {
            navPointDepth = max(navPointDepth - 1, 0)
            return
        }
        guard elementName == "text" else { return }
        isInsideNavLabelText = false
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            pendingTitle = trimmed
        }
    }
}
