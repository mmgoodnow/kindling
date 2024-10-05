import Combine
import SwiftUI

struct SearchView: View {
	let progressReporter = ProgressReporter()

	@State private var query: String = ""
	@State private var searchResults: [SearchResult] = []
	@State private var downloadedFilename: String?
	@State private var downloadedData: Data?
	@State private var errorMessage: String?
	@State private var isShowingMailComposer = false

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
			SearchResultsView(
				searchResults: searchResults,
				downloader: downloader
			).backgroundStyle(.background)

			if let error = errorMessage {
				Text("Error: \(error)")
					.font(.footnote)
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
		Task {
			do {
				searchResults = try await downloader.search(
					query: query, progressReporter: progressReporter)

				try await Task.sleep(for: .seconds(0.5))
				withAnimation {
					progressReporter.reset()
				}
			} catch {
				progressReporter.reset()
				errorMessage = "Search failed: \(error.localizedDescription)"
			}
		}
	}
}

#Preview {
	ContentView()
}
