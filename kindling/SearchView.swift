import Combine
import SwiftUI

struct SearchView: View {
  let progressReporter = ProgressReporter()
  let minSearchLength = 3

  @EnvironmentObject var userSettings: UserSettings

  @State private var query: String = ""
  @State private var searchedQuery: String = ""
  @State private var searchResults: [SearchResult]? = nil
  @State private var errorMessage: String?

  var downloader: EBookDownloader

  var body: some View {
    VStack {
      if let status = progressReporter.status {
        ProgressView(value: progressReporter.progress ?? 0)
          .padding(.horizontal, 16)
          .opacity(progressReporter.progress == nil ? 0 : 1)
        Text(status)
          .font(.caption)
          .foregroundStyle(.gray)
      }
      if let searchResults = searchResults {
        SearchResultsView(
          query: searchedQuery,
          searchResults: searchResults,
          downloader: downloader
        ).backgroundStyle(.background)
      } else {
        ContentUnavailableView {
          Label("Search", systemImage: "magnifyingglass")
        } description: {
          if query.count < minSearchLength {
            Text("Enter at least 3 characters.")
          }
        }
      }

      if let error = errorMessage {
        Text("Error: \(error)")
          .font(.caption)
          .foregroundColor(.red)
      }
    }
    .navigationTitle("Kindling")
    .searchable(
      text: $query, prompt: "Search by author, title, or series"
    )
    .onSubmit(of: .search, doSearch)

  }

  private func doSearch() {
    guard query.count >= minSearchLength else { return }
    Task {
      do {
        searchResults = try await downloader.search(
          query: query,
          searchBot: userSettings.searchBot,
          nickname: userSettings.ircNick,
          progressReporter: progressReporter
        )
        searchedQuery = query

        try await Task.sleep(for: .seconds(0.5))
        withAnimation {
          progressReporter.reset()
        }
      } catch let ebookError as EBookError {
        progressReporter.reset()
        errorMessage =
          "Search failed: \(ebookError.localizedDescription)"
      } catch {
        progressReporter.reset()
        errorMessage = "Search failed: \(error.localizedDescription)"
      }
    }
  }
}

#Preview {
  ContentView()
    .environmentObject(UserSettings())
}
