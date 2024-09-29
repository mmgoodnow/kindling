import SwiftUI

enum RegistrationStatus {
	case failed
	case ready
	case loading
}

struct MainView: View {
	@State private var query: String = ""
	@State private var registrationStatus: RegistrationStatus = .loading
	@State private var searchResults: [SearchResult] = []
	@State private var isDownloading: Bool = false
	@State private var downloadedFilename: String?
	@State private var downloadedData: Data?
	@State private var errorMessage: String?
	@State private var isShowingMailComposer = false
	@State private var progress: Double? = nil
	@State private var mostRecentProgressUpdate: String? = nil
	@AppStorage("kindleEmailAddress") private var kindleEmailAddress =
		"wengvince_z6xtde@kindle.com"

	var downloader: EBookDownloader

	var registrationStatusDotColor: Color {
		switch registrationStatus {
		case .failed:
			Color.red
		case .ready:
			Color.green
		case .loading:
			Color.yellow
		}
	}

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

				if let error = errorMessage {
					Text("Error: \(error)")
						.font(.footnote)
						.foregroundColor(.red)
				}
			}.onAppear {
				Task {
					do {
						registrationStatus = .loading
						try await downloader.start()
						registrationStatus = .ready
					} catch {
						registrationStatus = .failed
					}
				}
			}
			.navigationTitle("Kindling")
			.toolbar {
				ToolbarItem {
					Circle()
						.fill(registrationStatusDotColor)
						.frame(width: 10, height: 10)

				}
				ToolbarItem {
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
							subject: filename,
							messageBody:
								"Make sure your email is an approved sender!",
							recipient: kindleEmailAddress,
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
