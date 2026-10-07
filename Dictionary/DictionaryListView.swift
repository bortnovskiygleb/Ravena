import SwiftUI
import SwiftData

struct DictionaryListView: View {
    @Query private var words: [SavedWord]
    @Query private var dueWords: [SavedWord]
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingReview = false
    @State private var selectedWord: SavedWord?

    @State private var isAscending = false

    init() {
        _words = Query(sort: \SavedWord.dateAdded, order: .reverse)

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
                ScrollView {
                    VStack(spacing: 24) {
                        Button {
                            isShowingReview = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.stack.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Повторить слова")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(dueWords.count > 0 ? "\(dueWords.count)" : "0")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                            ForEach(groupedWords, id: \.date) { group in
                                Section {
                                    ForEach(group.words) { entry in
                                        card(for: entry)
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    modelContext.delete(entry)
                                                } label: {
                                                    Label("Удалить", systemImage: "trash")
                                                }
                                            }
                                    }
                                } header: {
                                    Text(sectionTitle(for: group.date))
                                        .font(.title3.bold())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .background(Color(uiColor: .systemGroupedBackground))
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        isAscending.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .disabled(words.isEmpty)
            }
        }
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

    private var groupedWords: [(date: Date, words: [SavedWord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: words) { word in
            let shifted = calendar.date(byAdding: .hour, value: -4, to: word.dateAdded) ?? word.dateAdded
            return calendar.startOfDay(for: shifted)
        }
        
        let mapped = grouped.map { (date: $0.key, words: $0.value) }
        
        // Ensure inner arrays are sorted consistently
        let sortedMapped = mapped.map { item in
            (date: item.date, words: isAscending 
                ? item.words.sorted(by: { $0.dateAdded < $1.dateAdded }) 
                : item.words.sorted(by: { $0.dateAdded > $1.dateAdded }))
        }
        
        return isAscending 
            ? sortedMapped.sorted { $0.date < $1.date }
            : sortedMapped.sorted { $0.date > $1.date }
    }

    private func sectionTitle(for logicalDate: Date) -> String {
        let calendar = Calendar.current
        let now = Date.now
        let shiftedNow = calendar.date(byAdding: .hour, value: -4, to: now) ?? now
        let logicalToday = calendar.startOfDay(for: shiftedNow)
        
        if logicalDate == logicalToday {
            return "Сегодня"
        }
        
        let logicalYesterday = calendar.date(byAdding: .day, value: -1, to: logicalToday)
        if logicalDate == logicalYesterday {
            return "Вчера"
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: logicalDate)
    }

    private func card(for entry: SavedWord) -> some View {
        Button {
            selectedWord = entry
        } label: {
            VStack(alignment: .center, spacing: 8) {
                Text(entry.word)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(entry.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
