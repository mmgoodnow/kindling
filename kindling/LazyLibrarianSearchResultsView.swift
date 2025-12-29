import SwiftUI

struct LazyLibrarianSearchResultsView: View {
  @ObservedObject var viewModel: LazyLibrarianViewModel
  @EnvironmentObject var userSettings: UserSettings
  let client: LazyLibrarianServing
  @State private var pendingItemIDs: Set<String> = []

  var body: some View {
    List {
      if let error = viewModel.errorMessage {
        Text(error)
          .foregroundStyle(.red)
          .font(.caption)
      }

      if viewModel.searchResults.isEmpty {
        ContentUnavailableView(
          "No Results",
          systemImage: "magnifyingglass"
        )
      } else {
        ForEach(viewModel.searchResults) { book in
          LazyLibrarianSearchResultRow(
            viewModel: viewModel,
            book: book,
            client: client,
            pendingItemIDs: $pendingItemIDs
          )
        }
      }
    }
    .navigationTitle("Search")
  }
}

struct LazyLibrarianSearchResultRow: View {
  @ObservedObject var viewModel: LazyLibrarianViewModel
  @EnvironmentObject var userSettings: UserSettings
  let book: LazyLibrarianBook
  let client: LazyLibrarianServing
  @Binding var pendingItemIDs: Set<String>

  var body: some View {
    let isPending =
      pendingItemIDs.contains(book.id)
      && viewModel.progressForBookID(book.id) == nil
    let progress = viewModel.progressForBookID(book.id)
    let matchingItem = viewModel.libraryItems.first(where: { $0.id == book.id })
    let effectiveItem =
      matchingItem
      ?? (isPending
        ? LazyLibrarianLibraryItem(
          id: book.id,
          title: book.title,
          author: book.author,
          status: .requested,
          audioStatus: .requested,
          bookAdded: .now
        )
        : nil)
    let shouldShowGetButton = effectiveItem == nil

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        let coverURL = book.coverImageURL.flatMap { url -> URL? in
          if url.scheme != nil { return url }
          return lazyLibrarianAssetURL(
            baseURLString: userSettings.lazyLibrarianURL,
            path: url.absoluteString
          )
        }
        podibleCoverView(url: coverURL)
        VStack(alignment: .leading, spacing: 4) {
          Text(book.title)
            .font(.headline)
            .lineLimit(2)
          Text(book.author)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 6) {
          if let item = effectiveItem {
            lazyLibrarianStatusCluster(
              item: item,
              progress: progress,
              shouldOfferSearch: { status in
                viewModel.shouldOfferSearch(status: status)
              }
            )
          } else if shouldShowGetButton {
            Group {
              if isPending {
                Button {
                  Task {
                    await viewModel.request(
                      book,
                      using: client
                    )
                  }
                } label: {
                  Text("GET")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
              } else {
                Button {
                  pendingItemIDs.insert(book.id)
                  viewModel.beginOptimisticRequest(for: book)
                  Task {
                    await viewModel.request(
                      book,
                      using: client
                    )
                    let updated = viewModel
                      .searchResults
                      .first(where: {
                        $0.id == book.id
                      })
                    let shouldWait =
                      updated.map {
                        viewModel
                          .shouldShowDownloadProgress(
                            status: $0.status,
                            audioStatus: $0
                              .audioStatus
                          )
                      } ?? false
                    if shouldWait == false
                      || viewModel.progressForBookID(
                        book.id
                      ) != nil
                    {
                      pendingItemIDs.remove(
                        book.id
                      )
                    }
                  }
                } label: {
                  Text("GET")
                }
                .buttonStyle(.bordered)
              }
            }
            .controlSize(.small)
            .tint(.accentColor)
            .clipShape(Capsule())
            .disabled(
              isPending || book.status == .requested
                || book.status == .wanted
            )
          }
        }
      }
    }
    .onChange(of: viewModel.progressForBookID(book.id)?.updatedAt) { _, _ in
      pendingItemIDs.remove(book.id)
    }
  }
}

#Preview {
  let viewModel = LazyLibrarianViewModel()
  viewModel.searchResults = [
    LazyLibrarianBook(
      id: "1",
      title: "They Both Die at the End",
      author: "Adam Silvera",
      status: .requested,
      audioStatus: .requested,
      coverImageURL: URL(
        string:
          "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1315601232l/11869272._SX98_.jpg"
      )
    ),
    LazyLibrarianBook(
      id: "2",
      title: "The Secret History",
      author: "Donna Tartt",
      status: .unknown
    ),
  ]
  viewModel.downloadProgressByBookID["1"] =
    LazyLibrarianViewModel.DownloadProgress(
      ebook: 42,
      audiobook: 18,
      ebookFinished: false,
      audiobookFinished: false,
      ebookSeen: true,
      audiobookSeen: true,
      updatedAt: .now
    )

  return NavigationStack {
    LazyLibrarianSearchResultsView(
      viewModel: viewModel,
      client: LazyLibrarianMockClient()
    )
    .environmentObject(UserSettings())
  }
}
