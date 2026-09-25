import Foundation
import NaturalLanguage

struct TappableWord {
    let text: String
    let range: Range<String.Index>
}

enum WordTokenizer {

    /// Splits a paragraph's plain text into individual words, correctly handling
    /// punctuation and contractions (e.g. "don't" stays one token, not "don" + "t").
    /// Call this on-demand when rendering a paragraph — no need to precompute
    /// and store word lists for the whole book.
    static func words(in text: String) -> [TappableWord] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var results: [TappableWord] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            // Skip pure punctuation/whitespace tokens.
            if word.rangeOfCharacter(from: .letters) != nil {
                results.append(TappableWord(text: word, range: range))
            }
            return true
        }
        return results
    }
}

/*
Usage once the user taps a location inside a UITextView / TextKit 2 layout:

1. Convert the tap point to a character index in the paragraph's plainText
   (via NLTextLayoutManager / NSTextLayoutFragment hit-testing).
2. Find which TappableWord's range contains that index.
3. Send `word.text` + the full paragraph text (as context) to the translation service.
*/
