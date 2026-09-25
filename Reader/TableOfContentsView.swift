import SwiftUI

struct TableOfContentsView: View {
    let entries: [EPUBTOCEntry]
    let currentChapterIndex: Int
    let onSelect: (EPUBTOCEntry) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        HStack {
                            Text(entry.title)
                                .font(font(forDepth: entry.depth))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .padding(.leading, CGFloat(entry.depth) * 20)
                            Spacer()
                            if entry.chapterIndex == currentChapterIndex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Содержание")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Top-level entries (depth 0 — a volume in a book that has them, or
    /// just the chapter itself in a book that doesn't) stand out as bold and
    /// larger; each nested level steps down in size/weight so the hierarchy
    /// reads at a glance, not just from the indentation alone.
    private func font(forDepth depth: Int) -> Font {
        switch depth {
        case 0: return .body.bold()
        case 1: return .subheadline
        default: return .footnote
        }
    }
}
