import Foundation
import NaturalLanguage

enum SentenceExtractor {

    /// A sentence longer than this is almost certainly a tokenizer failure —
    /// NLTokenizer found no sentence-ending punctuation for a long stretch
    /// (common in irregular/OCR'd text: abbreviations, mathematical
    /// notation, tables rendered as prose) — rather than a genuinely long
    /// sentence. Without this bound, such a "sentence" could run to several
    /// thousand characters, which both makes for a nonsensical translation
    /// prompt and can trip the backend's own input-length rejection
    /// (MAX_SENTENCE_LENGTH in backend/src/index.ts) — every tap on a word
    /// inside that same stretch would then fail the same way, every time,
    /// looking like a caching bug even though nothing is actually cached.
    private static let maxReasonableSentenceLength = 500
    private static let fallbackWindowRadius = 150

    /// Returns the sentence containing the given UTF-16 offset.
    /// UITextView positions (from `offset(from:to:)`) are UTF-16-based, hence the conversion.
    static func sentence(containingUTF16Offset utf16Offset: Int, in text: String) -> String? {
        guard let utf16Index = text.utf16.index(
            text.utf16.startIndex, offsetBy: utf16Offset, limitedBy: text.utf16.endIndex
        ), let index = String.Index(utf16Index, within: text) else {
            return nil
        }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var result: String?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if range.contains(index) || range.upperBound == index {
                result = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                return false // stop enumeration once found
            }
            return true
        }

        if let result, result.utf16.count <= maxReasonableSentenceLength {
            return result
        }
        // Either NLTokenizer found nothing, or found something implausibly
        // long — both fall back to a bounded plain-text window around the
        // tapped word instead.
        return boundedWindow(around: index, in: text)
    }

    /// Some text before and after `index`, without trying to respect
    /// sentence boundaries — the fallback used when NLTokenizer's own
    /// sentence detection can't be trusted for this text.
    private static func boundedWindow(around index: String.Index, in text: String) -> String? {
        let centerOffset = text.distance(from: text.startIndex, to: index)
        let lowerOffset = max(centerOffset - fallbackWindowRadius, 0)
        let upperOffset = min(centerOffset + fallbackWindowRadius, text.count)

        guard lowerOffset < upperOffset,
              let lower = text.index(text.startIndex, offsetBy: lowerOffset, limitedBy: text.endIndex),
              let upper = text.index(text.startIndex, offsetBy: upperOffset, limitedBy: text.endIndex)
        else {
            return nil
        }

        let window = String(text[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
        return window.isEmpty ? nil : window
    }
}
