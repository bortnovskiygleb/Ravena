import SwiftUI
import SwiftData

struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var dueWords: [SavedWord] = []
    @State private var currentIndex = 0
    @State private var isRevealed = false

    var body: some View {
        NavigationStack {
            Group {
                if dueWords.isEmpty {
                    emptyState
                } else if currentIndex >= dueWords.count {
                    completionState
                } else {
                    cardView(for: dueWords[currentIndex])
                }
            }
            .navigationTitle("Повторение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadDueWords)
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Нечего повторять")
                .font(.headline)
            Text("Все слова уже повторены — загляните позже.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var completionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("Готово!")
                .font(.title2.bold())
            Text("Повторили \(dueWords.count) \(wordForm(dueWords.count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Card

    private func cardView(for entry: SavedWord) -> some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(currentIndex), total: Double(dueWords.count))
                .padding(.horizontal, 32)
                .padding(.top, 16)

            Spacer()

            VStack(spacing: 12) {
                Text(entry.word)
                    .font(.system(size: 40, weight: .bold))
                    .multilineTextAlignment(.center)

                if isRevealed {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text(entry.translation)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            if let partOfSpeech = entry.partOfSpeech {
                                Text(partOfSpeech)
                                    .font(.subheadline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(entry.contextSentence)
                            .font(.body)
                            .italic()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 8)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            if isRevealed {
                ratingButtons(for: entry)
            } else {
                Button {
                    withAnimation { isRevealed = true }
                } label: {
                    Text("Показать перевод")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            }
        }
        .padding(.bottom, 24)
    }

    private func ratingButtons(for entry: SavedWord) -> some View {
        HStack(spacing: 12) {
            ratingButton(title: "Забыл", color: .red) { rate(entry, .again) }
            ratingButton(title: "Помню", color: .blue) { rate(entry, .good) }
            ratingButton(title: "Легко", color: .green) { rate(entry, .easy) }
        }
        .padding(.horizontal, 24)
    }

    private func ratingButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    // MARK: - Actions

    private func rate(_ entry: SavedWord, _ rating: ReviewRating) {
        entry.applyReview(rating: rating)
        try? modelContext.save()
        withAnimation {
            isRevealed = false
            currentIndex += 1
        }
    }

    private func loadDueWords() {
        let now = Date.now
        let descriptor = FetchDescriptor<SavedWord>(
            predicate: #Predicate { $0.nextReviewDate <= now },
            sortBy: [SortDescriptor(\.nextReviewDate)]
        )
        dueWords = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Russian plural agreement for "слово" (1 слово / 2 слова / 5 слов) —
    /// unlike the reader's page-count label, "слово" is central to this
    /// screen's copy, so abbreviating around the grammar isn't a good look
    /// here the way "5 стр." was for pages.
    private func wordForm(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "слово" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "слова" }
        return "слов"
    }
}
