import SwiftUI
import SwiftData

struct DictionaryListView: View {
    @Query private var words: [SavedWord]
    @Query private var dueWords: [SavedWord]
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingReview = false
    @State private var selectedWord: SavedWord?

    init() {
        _words = Query(sort: \SavedWord.dateAdded, order: .reverse)

        // #Predicate can't build an expression tree directly from `Date.now`
        // (a computed static property) — capturing it as a plain local
        // constant first, and referencing *that* inside the predicate, is
        // the standard workaround: a captured value compiles fine, a direct
        // Date.now reference inside the closure does not.
        let now = Date.now
        _dueWords = Query(
            filter: #Predicate<SavedWord> { $0.nextReviewDate <= now },
            sort: [SortDescriptor(\SavedWord.nextReviewDate)]
        )
    }

    var body: some View {
        Group {
            if words.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        Button {
                            isShowingReview = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.stack.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Повторить слова")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if dueWords.count > 0 {
                                    Text("\(dueWords.count)")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("0")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        ForEach(words) { entry in
                            Button {
                                selectedWord = entry
                            } label: {
                                row(for: entry)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
        }
        .overlay {
            if isShowingReview {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .blur(radius: isShowingReview ? 5 : 0)
        .animation(.easeInOut(duration: 0.3), value: isShowingReview)
        .navigationTitle("Мой словарь")
        .sheet(isPresented: $isShowingReview) {
            ReviewSessionView()
        }
        .sheet(item: $selectedWord) { entry in
            NavigationStack {
                DictionaryEntryDetailView(entry: entry)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Готово") {
                                selectedWord = nil
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func row(for entry: SavedWord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.word)
                .font(.headline)
            Spacer()
            Text(entry.translation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "book")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Словарь пуст")
                .font(.headline)
            Text("Слова, которые вы сохраните во время чтения, появятся здесь")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(words[index])
        }
    }
}
