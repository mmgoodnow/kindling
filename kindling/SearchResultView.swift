import SwiftUI

struct SearchResultView: View {
	let result: SearchResult
	let downloader: EBookDownloader?

	let progressReporter = ProgressReporter()

	@EnvironmentObject var userSettings: UserSettings
	@State private var isExportModalOpen = false
	@State private var downloadedFile: BookFile?
	@State private var error: EBookError?
	@State private var isExported = false

	private func download() {
		guard let downloader = downloader else { return }

		Task {
			if downloadedFile == nil {
				do {
					downloadedFile = try await downloader.download(
						searchResult: result,
						progressReporter: progressReporter
					)
					progressReporter.reset()
				} catch {
					self.error = (error as! EBookError)
				}
			}
			isExportModalOpen = true
		}
	}

	var body: some View {
		HStack {
			VStack(alignment: .leading) {
				if let metadata = result.metadata {
					Text(metadata.title)
						.font(.headline)
					if let series = metadata.series {
						Text(metadata.author)
							.font(.subheadline)
						Text(series)
							.font(.subheadline)

					} else {
						Text(metadata.author)
							.font(.subheadline)
					}
				} else {
					Text(result.filename)
						.font(.headline)
				}
				Text("\(result.bot)\(result.size.map { " " + $0 } ?? "")")
					.font(.subheadline)
					.foregroundStyle(.gray)
				if let error = error {
					Text(error.localizedDescription)
						.font(.caption)
						.foregroundStyle(.red)
				} else if let progress = progressReporter.status {
					Text(progress)
						.font(.caption)
						.foregroundStyle(.gray)
				} else if isExported {
					Text("Exported")
						.font(.caption)
						.foregroundStyle(.gray)
				} else if downloadedFile != nil {
					Text("Downloaded")
						.font(.caption)
						.foregroundStyle(.gray)

				}
			}
			Spacer(minLength: 18)
			if error != nil {
				Image(systemName: "exclamationmark.circle")
					.font(.title2)
					.foregroundColor(.red)
			} else if let progress = progressReporter.progress {
				ProgressView(value: progress)
					.progressViewStyle(.circular)
			} else {
				VStack {
					Button(action: download) {
						if isExported {
							Image(systemName: "checkmark.circle")
								.font(.title2)
								.foregroundColor(.green)
						} else {
							Image(systemName: "arrow.down.circle")
								.font(.title2)
								.foregroundColor(.blue)
						}
					}
				}
			}
		}.exporter(
			downloadedFile: downloadedFile,
			kindleEmailAddress: userSettings.kindleEmailAddress,
			isExportModalOpen: $isExportModalOpen,
			isExported: $isExported
		)
	}
}
