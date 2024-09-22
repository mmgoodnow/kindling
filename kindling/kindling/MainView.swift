import SwiftUI

struct MainView: View {
	@State private var query: String = ""
	@State private var searchResults: [SearchResult] = []
	@State private var isDownloading: Bool = false
	@State private var downloadedFilename: String?
	@State private var errorMessage: String?

	var downloader: EBookDownloader

	var body: some View {
		NavigationStack {
			VStack {
				// Search Bar
				HStack {
					TextField("Search for eBooks", text: $query)
						.textFieldStyle(RoundedBorderTextFieldStyle())
						.padding()

					Button(action: searchForEBooks) {
						Text("Search")
					}
					.padding(.trailing)
				}

				SearchResultsView(searchResults: searchResults, onDownload: download)

				// Download status
				if let filename = downloadedFilename {
					Text("Downloaded: \(filename)")
						.font(.footnote)
						.foregroundColor(.green)
				}

				if let error = errorMessage {
					Text("Error: \(error)")
						.font(.footnote)
						.foregroundColor(.red)
				}
			}.onAppear {
				Task {
					do {
						// Call the start method to register with the IRC server
						try await downloader.start()
					} catch {
						errorMessage =
							"Failed to start: \(error.localizedDescription)"
					}
				}
			}
			.navigationTitle("Kindling")
		}
	}

	// Search action
	private func searchForEBooks() {
		Task {
			do {
				searchResults = try await downloader.searchForEBook(query: query)
			} catch {
				errorMessage = "Search failed: \(error.localizedDescription)"
			}
		}
	}

	// Download action
	private func download(_ result: SearchResult) {
		isDownloading = true
		Task {
			do {
				let (filename, _) = try await downloader.download(
					searchResult: result)
				downloadedFilename = filename
				isDownloading = false
			} catch {
				errorMessage = "Download failed: \(error.localizedDescription)"
				isDownloading = false
			}
		}
	}
}
