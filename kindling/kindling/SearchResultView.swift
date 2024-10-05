import SwiftUI

struct SearchResultView: View {
	let result: SearchResult
	let downloader: EBookDownloader?

	let progressReporter = ProgressReporter()

	@EnvironmentObject var userSettings: UserSettings
	@State private var isShowingMailComposer = false
	@State private var downloadedFile: BookFile?
	@State private var error: EBookError?

	private func download() {
		Task {
			do {
				if let (filename, data) = try await downloader?.download(
					searchResult: result, progressReporter: progressReporter)
				{
					#if os(iOS)
						isShowingMailComposer = true
					#endif
					#if os(macOS)
						let downloadsDirectory = FileManager.default.urls(
							for: .downloadsDirectory,
							in: .userDomainMask
						).first!
						try data.write(
							to: downloadsDirectory.appending(
								path: filename)
						)
					#endif
				}
			} catch {
				self.error = error as? EBookError
			}
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
				Text("\(result.bot)\(result.size.map {" " + $0} ?? "")")
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
				}
			}
			Spacer(minLength: 18)
			if error != nil {
				Image(systemName: "exclamationmark.circle")
					.font(.title2)
					.foregroundColor(.red)
			} else if let status = progressReporter.status {
				ProgressView()
			} else {
				Button(action: download) {
					Image(systemName: "arrow.down.circle")
						.font(.title2)
						.foregroundColor(.blue)
				}
			}
		}.sheet(isPresented: $isShowingMailComposer) {
			#if os(iOS)
				if let file = downloadedFile {
					MailComposerView(
						subject: file.filename,
						messageBody:
							"Make sure your email is an approved sender!",
						recipient: userSettings.kindleEmailAddress,
						attachmentData: file.data,
						attachmentMimeType:
							"application/epub+zip",
						attachmentFileName: file.filename
					)
				}
			#endif
		}
	}
}

#Preview {
	List {
		SearchResultView(
			result: SearchResult(
				from:
					"!Dumbledore Julianna Keyes - (Big Friends 01) - Big Wild Love Adventure.epub"
			)!,
			downloader: nil)
		SearchResultView(
			result: SearchResult(
				from: "!Dumbledore Julianna Keyes - Big Wild Love Adventure.epub")!,
			downloader: nil)
	}
}
