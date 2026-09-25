import SwiftUI
import SwiftData
import UIKit

struct LibraryListView: View {
    @Query(sort: \LibraryBook.dateAdded, order: .reverse) private var books: [LibraryBook]
    @Environment(\.modelContext) private var modelContext

    @State private var isShowingPicker = false
    @State private var importAlertTitle = ""
    @State private var importAlertMessage: String?

    /// The library screen doesn't know how to build a reader screen itself
    /// (that's UIKit territory) — it just reports which book was tapped.
    var onOpenBook: (LibraryBook) -> Void

    var body: some View {
        Group {
            if books.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(books) { book in
                        Button {
                            onOpenBook(book)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                coverThumbnail(for: book)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(book.author)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if book.progressFraction > 0 {
                                        HStack(spacing: 6) {
                                            ProgressView(value: book.progressFraction)
                                                .frame(maxWidth: 120)
                                            Text("\(Int((book.progressFraction * 100).rounded()))%")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Библиотека")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingPicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingPicker) {
            EPUBFilePicker { url in
                isShowingPicker = false
                importBook(from: url)
            }
        }
        .alert(
            importAlertTitle,
            isPresented: Binding(
                get: { importAlertMessage != nil },
                set: { if !$0 { importAlertMessage = nil } }
            ),
            actions: { Button("OK") { importAlertMessage = nil } },
            message: { Text(importAlertMessage ?? "") }
        )
    }

    /// Books without a declared cover (or one that fails to decode) fall back
    /// to a plain placeholder rather than an empty gap — keeps every row the
    /// same shape regardless of which books happen to have real artwork.
    @ViewBuilder
    private func coverThumbnail(for book: LibraryBook) -> some View {
        Group {
            if let data = book.coverImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                    Image(systemName: "book.closed")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 44, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Библиотека пуста")
                .font(.headline)
            Text("Нажмите +, чтобы добавить книгу в формате EPUB")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func importBook(from url: URL) {
        Task {
            do {
                try await BookImporter(modelContext: modelContext).importBook(from: url)
            } catch BookImportError.duplicate(let existingTitle) {
                importAlertTitle = "Уже в библиотеке"
                importAlertMessage = "«\(existingTitle)» — тот же файл уже есть в вашей библиотеке."
            } catch {
                importAlertTitle = "Не удалось импортировать книгу"
                importAlertMessage = "Проверьте, что файл действительно в формате EPUB, и попробуйте снова."
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let book = books[index]
            // Best-effort: if this fails (permissions, file briefly in use),
            // it's not a permanent orphan — LibraryFileReconciler sweeps
            // Documents/Books/ against the database on every launch and
            // removes anything left over from here.
            try? FileManager.default.removeItem(at: book.fileURL)
            modelContext.delete(book)
        }
    }
}
