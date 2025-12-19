import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LazyLibrarianView: View {
	@EnvironmentObject var userSettings: UserSettings
	@StateObject private var viewModel = LazyLibrarianViewModel()
	@State private var isShowingSearchResults = false
	@State private var isShowingPodibleExporter = false
	@State private var podibleExportDocument: EpubDocument?
	@State private var podibleExportFilename: String = "book.epub"
	@State private var podibleErrorMessage: String?
	@State private var isPodibleDownloading = false

	let clientOverride: LazyLibrarianServing?

	init(client: LazyLibrarianServing? = nil) {
		self.clientOverride = client
	}

	private var configuredClient: LazyLibrarianServing? {
		if let clientOverride {
			return clientOverride
		}
		guard
			let url = URL(string: userSettings.lazyLibrarianURL),
			userSettings.lazyLibrarianURL.isEmpty == false,
			userSettings.lazyLibrarianAPIKey.isEmpty == false
		else {
			return nil
		}
		return LazyLibrarianClient(baseURL: url, apiKey: userSettings.lazyLibrarianAPIKey)
	}

	var body: some View {
		Group {
			if let client = configuredClient {
				content(client: client)
			} else {
				ContentUnavailableView {
					Label("LazyLibrarian", systemImage: "books.vertical")
				} description: {
					Text("Add your LazyLibrarian URL and API key in Settings to request books and see request status.")
				}
				.navigationTitle("Library")
			}
		}
	}

	@ViewBuilder
	private func content(client: LazyLibrarianServing) -> some View {
		List {
			if let error = viewModel.errorMessage {
				Text(error)
					.foregroundStyle(.red)
					.font(.caption)
			}

			if let podibleError = podibleErrorMessage {
				Text(podibleError)
					.foregroundStyle(.red)
					.font(.caption)
			}

			if viewModel.requests.isEmpty {
				Text("No requests yet.")
					.foregroundStyle(.secondary)
			} else {
				ForEach(viewModel.requests) { request in
					requestRow(request, client: client)
				}
			}
		}
		#if os(iOS)
			.listStyle(.insetGrouped)
	#else
			.listStyle(.inset)
	#endif
		.navigationTitle("Library")
		.onAppear {
			Task {
				await viewModel.loadRequests(using: client)
			}
		}
		.searchable(text: $viewModel.query, prompt: "Search")
		.onSubmit(of: .search) {
			Task {
				await viewModel.search(using: client)
				isShowingSearchResults = true
			}
		}
		.navigationDestination(isPresented: $isShowingSearchResults) {
			LazyLibrarianSearchResultsView(
				viewModel: viewModel,
				client: client
			)
		}
		.fileExporter(
			isPresented: $isShowingPodibleExporter,
			document: podibleExportDocument,
			contentType: .epub,
			defaultFilename: podibleExportFilename
		) { _ in
			podibleExportDocument = nil
		}
	}

	private func startPodibleDownload(author: String, title: String) async {
		guard let epubURL = podibleEpubURL(baseURLString: userSettings.podibleURL, author: author, title: title) else { return }
		isPodibleDownloading = true
		podibleErrorMessage = nil
		do {
			let localURL = try await PodibleClient(baseURLString: userSettings.podibleURL).downloadEpub(from: epubURL)
			podibleExportFilename = sanitizeFilename(title).appending(".epub")
			podibleExportDocument = EpubDocument(url: localURL)
			isShowingPodibleExporter = true
		} catch {
			podibleErrorMessage = error.localizedDescription
		}
		isPodibleDownloading = false
	}

	private func sanitizeFilename(_ value: String) -> String {
		podibleSanitizeFilename(value)
	}

	private func requestRow(_ request: LazyLibrarianRequest, client: LazyLibrarianServing) -> some View {
		let progress = viewModel.progressForBookID(request.id)
		let shouldShowProgress = viewModel.shouldShowDownloadProgress(
			status: request.status,
			audioStatus: request.audioStatus
		) && progress != nil

		return VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .center, spacing: 12) {
				podibleCoverView(
					url: podibleCoverURL(
						baseURLString: userSettings.podibleURL,
						author: request.author,
						title: request.title
					)
				)
				VStack(alignment: .leading, spacing: 4) {
					Text(request.title)
						.font(.headline)
						.lineLimit(2)
					Text(request.author)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
				Spacer(minLength: 8)
				VStack(alignment: .trailing, spacing: 6) {
					if let progress, shouldShowProgress {
						lazyLibrarianProgressCircles(progress: progress)
					} else {
						Button {
							Task {
								await startPodibleDownload(
									author: request.author,
									title: request.title
								)
							}
						} label: {
							Image(systemName: "book.closed")
						}
						.buttonStyle(.bordered)
						.controlSize(.small)
						.clipShape(Capsule())
						.disabled(
							isPodibleDownloading
								|| podibleEpubURL(
									baseURLString: userSettings.podibleURL,
									author: request.author,
									title: request.title
								) == nil
						)
					}
				}
			}
		}
		.padding(.vertical, 4)
		.listRowSeparator(.visible)
		.listRowInsets(EdgeInsets())
		.alignmentGuide(.listRowSeparatorLeading) { _ in 56 }
	}
}

@ViewBuilder
func lazyLibrarianProgressCircles(progress: LazyLibrarianViewModel.DownloadProgress) -> some View {
	VStack(alignment: .trailing, spacing: 6) {
		HStack(spacing: 6) {
			Text("eBook")
				.font(.caption2)
				.foregroundStyle(.secondary)
			ProgressView(value: Double(progress.ebook), total: 100)
				.progressViewStyle(.circular)
				.controlSize(.small)
				.tint(progress.ebookFinished ? .green : .blue)
				.frame(width: 16, height: 16)
		}
		HStack(spacing: 6) {
			Text("Audio")
				.font(.caption2)
				.foregroundStyle(.secondary)
			ProgressView(value: Double(progress.audiobook), total: 100)
				.progressViewStyle(.circular)
				.controlSize(.small)
				.tint(progress.audiobookFinished ? .green : .blue)
				.frame(width: 16, height: 16)
		}
	}
}

@ViewBuilder
func podibleCoverView(url: URL?) -> some View {
	if let url {
		AsyncImage(url: url) { phase in
			switch phase {
			case .empty:
				podibleCoverPlaceholder()
			case .success(let image):
				image
					.resizable()
					.scaledToFill()
			default:
				podibleCoverPlaceholder()
			}
		}
		.frame(width: 44, height: 64)
		.clipShape(RoundedRectangle(cornerRadius: 6))
	}
}

func podibleCoverPlaceholder() -> some View {
	RoundedRectangle(cornerRadius: 6)
		.fill(.quaternary)
		.frame(width: 44, height: 64)
		.overlay(
			Image(systemName: "book.closed")
				.font(.caption)
				.foregroundStyle(.secondary)
		)
}

fileprivate func podibleSanitizeFilename(_ value: String) -> String {
	let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
	if trimmed.isEmpty { return "book" }
	let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
	return trimmed.components(separatedBy: invalid).joined(separator: "-")
}

func podibleEpubURL(baseURLString: String, author: String, title: String) -> URL? {
	let slug = podibleSlugify("\(author) \(title)")
	return PodibleClient(baseURLString: baseURLString).epubURL(slug: slug)
}

func podibleCoverURL(baseURLString: String, author: String, title: String) -> URL? {
	let slug = podibleSlugify("\(author) \(title)")
	return PodibleClient(baseURLString: baseURLString).coverURL(slug: slug)
}

fileprivate func podibleSlugify(_ value: String) -> String {
	let trimmed = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
	let dashed = trimmed.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
	let collapsed = dashed.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
	return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

struct EpubDocument: FileDocument {
	static var readableContentTypes: [UTType] { [.epub] }

	let url: URL

	init(url: URL) {
		self.url = url
	}

	init(configuration: ReadConfiguration) throws {
		throw CocoaError(.fileReadUnknown)
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		let data = try Data(contentsOf: url)
		return FileWrapper(regularFileWithContents: data)
	}
}

extension UTType {
	static var epub: UTType {
		UTType(filenameExtension: "epub") ?? .data
	}
}

#Preview {
	NavigationStack {
		LazyLibrarianView(client: LazyLibrarianMockClient())
			.environmentObject(UserSettings())
	}
}
