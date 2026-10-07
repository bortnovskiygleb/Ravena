import SwiftUI

struct DictionaryEntryDetailView: View {
    @Bindable var entry: SavedWord

    /// Local draft so the user can type freely; we only write to SwiftData
    /// when the field loses focus (via `onChange(of:)` on the binding) rather
    /// than on every keystroke.
    @State private var transcriptionDraft: String = ""
    @FocusState private var transcriptionFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.word)
                        .font(.largeTitle.bold())
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
                }

                // MARK: Editable transcription
                labeledSection(title: "Транскрипция") {
                    TextField("например, /ˈwɔːtər/", text: $transcriptionDraft)
                        .font(.body.monospaced())
                        .focused($transcriptionFocused)
                        .submitLabel(.done)
                        .onSubmit { commitTranscription() }
                        .onChange(of: transcriptionFocused) { _, focused in
                            if !focused { commitTranscription() }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                labeledSection(title: "Контекст") {
                    Text(entry.contextSentence)
                        .font(.body)
                        .italic()
                }

                if let bookTitle = entry.bookTitle {
                    labeledSection(title: "Книга") {
                        Text(bookTitle)
                            .font(.body)
                    }
                }

                labeledSection(title: "Добавлено") {
                    Text(entry.dateAdded, style: .date)
                        .font(.body)
                }

                labeledSection(title: "Повторение") {
                    VStack(alignment: .leading, spacing: 4) {
                        if entry.nextReviewDate <= .now {
                            Text("Готово к повторению")
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text("Следующее повторение: \(entry.nextReviewDate, style: .date)")
                        }
                        if entry.repetitionCount > 0 {
                            Text("Повторений подряд без ошибок: \(entry.repetitionCount)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(entry.word)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { transcriptionDraft = entry.transcription ?? "" }
    }

    // MARK: - Helpers

    private func commitTranscription() {
        let trimmed = transcriptionDraft.trimmingCharacters(in: .whitespaces)
        entry.transcription = trimmed.isEmpty ? nil : trimmed
    }

    private func labeledSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}
