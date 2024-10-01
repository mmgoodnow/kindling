import Combine
import SwiftUI

struct MainView: View {
	@State private var query: String = ""
	@State private var searchResults: [SearchResult] = []
	@State private var isDownloading: Bool = false
	@State private var downloadedFilename: String?
	@State private var downloadedData: Data?
	@State private var errorMessage: String?
	@State private var isShowingMailComposer = false
	@AppStorage("kindleEmailAddress") private var kindleEmailAddress =
		"wengvince_z6xtde@kindle.com"

	var downloader: EBookDownloader
	@Bindable var reporter: ProgressReporter
	
	var body: some View {
		NavigationStack {
			VStack {
				if let status = reporter.status {
					ProgressView(value: reporter.progress ?? 0)
						.padding(.horizontal, 16)
						.opacity(reporter.progress == nil ? 0 : 1)
					Text(status)
						.font(.caption)
						.foregroundStyle(.gray)
				}
				SearchResultsView(
					searchResults: searchResults,
					onDownload: download
				).backgroundStyle(.background)

				if let error = errorMessage {
					Text("Error: \(error)")
						.font(.footnote)
						.foregroundColor(.red)
				}
			}
			.navigationTitle("Kindling")
			.sheet(isPresented: $isShowingMailComposer) {
				#if os(iOS)
					if let data = downloadedData,
						let filename = downloadedFilename
					{
						MailComposerView(
							subject: filename,
							messageBody:
								"Make sure your email is an approved sender!",
							recipient: kindleEmailAddress,
							attachmentData: data,
							attachmentMimeType:
								"application/epub+zip",
							attachmentFileName: filename
						)
					}
				#endif
			}.searchable(
				text: $query, prompt: "Search by author, title, or series"
			)
			.onSubmit(of: .search, doSearch)
		}

	}

	private func doSearch() {
		Task {
			do {
				searchResults = try await downloader.search(
					query: query)
				
				try await Task.sleep(for: .seconds(0.5))
				withAnimation {
					reporter.reset()
				}
			} catch {
				errorMessage = "Search failed: \(error.localizedDescription)"
			}
		}
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
