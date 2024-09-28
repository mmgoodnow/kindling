import SwiftUI

struct MainView: View {
	@State private var query: String = ""
	@State private var searchResults: [SearchResult] = []
	@State private var isDownloading: Bool = false
	@State private var downloadedFilename: String?
	@State private var downloadedData: Data?
	@State private var errorMessage: String?
	@State private var isShowingMailComposer = false
	@State private var progress: Double? = nil
	@State private var mostRecentProgressUpdate: String? = nil
	var downloader: EBookDownloader

	var body: some View {
		NavigationStack {
			VStack {
				if let status = mostRecentProgressUpdate {
					ProgressView(value: progress ?? 0)
						.padding(.horizontal, 16)
						.opacity(progress == nil ? 0 : 1)
					Text(status)
						.font(.caption)
						.foregroundStyle(.gray)
				}
				SearchResultsView(
					searchResults: searchResults,
					onDownload: download
				).backgroundStyle(.background)
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
						print("started")
					} catch {
						errorMessage =
							"Failed to start: \(error.localizedDescription)"
					}
				}
			}
			.navigationTitle("Kindling")
			.toolbar {
				ToolbarItem(placement: .automatic) {
					NavigationLink(destination: SettingsView()) {
						Image(systemName: "gear")
					}
				}
			}
			.sheet(isPresented: $isShowingMailComposer) {
				#if os(iOS)
					if let data = downloadedData,
						let filename = downloadedFilename
					{
						MailComposerView(
							subject: "Downloaded eBook",
							messageBody:
								"Here is the eBook you requested.",
							recipient: "recipient@example.com",
							attachmentData: data,
							attachmentMimeType: "application/epub+zip",
							attachmentFileName: filename
						)
					}
				#endif
			}.searchable(text: $query, prompt: "Search by author, title, or series")
			.onSubmit(of: .search, doSearch)
		}

	}

	private func doSearch() {
		Task {
			do {
				searchResults = try await downloader.searchForEBook(
					query: query, onProgress: handleProgressUpdate)
				progress = 1
				try await Task.sleep(for: .seconds(0.5))
				withAnimation {
					progress = nil
					mostRecentProgressUpdate = nil
				}
			} catch {
				errorMessage = "Search failed: \(error.localizedDescription)"
			}
		}
	}

	private func handleProgressUpdate(status: String, current: Int, total: Int) {
		progress = Double(current) / Double(total)
		mostRecentProgressUpdate = status
	}

	private func download(_ result: SearchResult) {
		isDownloading = true
		Task {
			do {
				let (filename, data) = try await downloader.download(
					searchResult: result)
				downloadedFilename = filename
				downloadedData = data
				isDownloading = false
				#if os(iOS)
					isShowingMailComposer = true
				#endif
				#if os(macOS)
					let downloadsDirectory = FileManager.default.urls(
						for: .downloadsDirectory,
						in: .userDomainMask
					).first!
					try data.write(
						to: downloadsDirectory.appending(path: filename)
					)
				#endif
			} catch {
				errorMessage = "Download failed: \(error.localizedDescription)"
				isDownloading = false
			}
		}
	}
}

#Preview {
	ContentView()
}
