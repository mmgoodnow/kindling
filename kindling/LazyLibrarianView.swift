import Foundation
import Kingfisher
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
		return LazyLibrarianClient(
			baseURL: url,
			apiKey: userSettings.lazyLibrarianAPIKey
		)
	}

	var body: some View {
		if let client = configuredClient {
			content(client: client)
		} else {
			ContentUnavailableView {
				Label("LazyLibrarian", systemImage: "books.vertical")
			} description: {
				Text(
					"Add your LazyLibrarian URL and API key in Settings to request books and see request status."
				)
			}
			.navigationTitle("Library")
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
		.navigationTitle("Library")
		.onAppear {
			Task {
				await viewModel.loadRequests(using: client)
			}
		}
		.toolbar {
			ToolbarItem {
				Button {
					Task {
						await viewModel.loadRequests(using: client)
					}
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.keyboardShortcut("r", modifiers: [.command])
			}
		}
		.refreshable {
			await viewModel.loadRequests(using: client)
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
		guard
			let epubURL = podibleEpubURL(
				baseURLString: userSettings.podibleURL,
				author: author,
				title: title
			)
		else { return }
		isPodibleDownloading = true
		podibleErrorMessage = nil
		do {
			let localURL = try await PodibleClient(
				baseURLString: userSettings.podibleURL
			).downloadEpub(from: epubURL)
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

	private func requestRow(
		_ request: LazyLibrarianRequest,
		client: LazyLibrarianServing
	) -> some View {
		let progress = viewModel.progressForBookID(request.id)

		return VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .center, spacing: 12) {
				podibleCoverView(
					url: lazyLibrarianAssetURL(
						baseURLString: userSettings.lazyLibrarianURL,
						path: request.bookImagePath
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
				HStack(spacing: 10) {
					lazyLibrarianEbookStatusRow(
						status: request.status,
						progressValue: progress?.ebook,
						progressFinished: progress?.ebookFinished ?? false,
						progressSeen: progress?.ebookSeen ?? false,
						canTriggerSearch: viewModel.canTriggerSearch(
							bookID: request.id,
							library: .ebook
						),
						shouldOfferSearch: viewModel.shouldOfferSearch(
							status: request.status
						),
						searchAction: {
							Task {
								await viewModel.triggerSearch(
									bookID: request.id,
									library: .ebook,
									using: client
								)
							}
						},
						downloadAction: {
							Task {
								await startPodibleDownload(
									author: request.author,
									title: request.title
								)
							}
						},
						canDownload: isPodibleDownloading == false
							&& podibleEpubURL(
								baseURLString: userSettings.podibleURL,
								author: request.author,
								title: request.title
							) != nil
					)
					lazyLibrarianAudioStatusRow(
						status: request.audioStatus,
						progressValue: progress?.audiobook,
						progressFinished: progress?.audiobookFinished ?? false,
						progressSeen: progress?.audiobookSeen ?? false,
						canTriggerSearch: viewModel.canTriggerSearch(
							bookID: request.id,
							library: .audio
						),
						shouldOfferSearch: viewModel.shouldOfferSearch(
							status: request.audioStatus
						),
						searchAction: {
							Task {
								await viewModel.triggerSearch(
									bookID: request.id,
									library: .audio,
									using: client
								)
							}
						}
					)
				}
			}
		}
	}
}

func lazyLibrarianEbookStatusRow(
	status: LazyLibrarianRequestStatus?,
	progressValue: Int?,
	progressFinished: Bool,
	progressSeen: Bool,
	canTriggerSearch: Bool,
	shouldOfferSearch: Bool,
	searchAction: @escaping () -> Void,
	downloadAction: @escaping () -> Void,
	canDownload: Bool
) -> some View {
	HStack(spacing: 6) {
		if status == .open {
			Button(action: downloadAction) {
				Image(systemName: "book.closed")
			}
			.buttonStyle(.plain)
			.controlSize(.regular)
			.foregroundStyle(Color.accentColor)
			.disabled(canDownload == false)
		} else if progressSeen {
			lazyLibrarianProgressCircle(
				value: progressValue ?? 0,
				tint: progressFinished ? .green : .blue,
				icon: "book.closed"
			)
		} else if shouldOfferSearch {
			Button(action: searchAction) {
				Image(systemName: "magnifyingglass")
			}
			.buttonStyle(.borderless)
			.controlSize(.small)
			.disabled(canTriggerSearch == false)
		} else {
			Color.clear
				.frame(width: 22, height: 22)
		}
	}
}

func lazyLibrarianAudioStatusRow(
	status: LazyLibrarianRequestStatus?,
	progressValue: Int?,
	progressFinished: Bool,
	progressSeen: Bool,
	canTriggerSearch: Bool,
	shouldOfferSearch: Bool,
	searchAction: @escaping () -> Void
) -> some View {
	HStack(spacing: 6) {
		if status == .open {
			Image(systemName: "headphones")
				.font(.body)
				.foregroundStyle(.secondary)
				.frame(width: 28, height: 28)
		} else if progressSeen {
			lazyLibrarianProgressCircle(
				value: progressValue ?? 0,
				tint: progressFinished ? .green : .blue,
				icon: "headphones"
			)
		} else if shouldOfferSearch {
			Button(action: searchAction) {
				Image(systemName: "magnifyingglass")
			}
			.buttonStyle(.borderless)
			.controlSize(.small)
			.disabled(canTriggerSearch == false)
		} else {
			Color.clear
				.frame(width: 22, height: 22)
		}
	}
}

@ViewBuilder
func lazyLibrarianProgressCircles(
	progress: LazyLibrarianViewModel.DownloadProgress,
	showLabels: Bool = true
) -> some View {
	VStack(alignment: .trailing, spacing: 6) {
		HStack(spacing: 6) {
			if showLabels {
				Text("eBook")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			lazyLibrarianProgressCircle(
				value: progress.ebook,
				tint: progress.ebookFinished ? .green : .blue,
				icon: "book.closed"
			)
		}
		HStack(spacing: 6) {
			if showLabels {
				Text("Audio")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			lazyLibrarianProgressCircle(
				value: progress.audiobook,
				tint: progress.audiobookFinished ? .green : .blue,
				icon: "headphones"
			)
		}
	}
}

func lazyLibrarianProgressCircle(value: Int, tint: Color, icon: String?) -> some View {
	let clamped = max(0, min(100, value))
	let progress = Double(clamped) / 100.0
	return ZStack {
		Circle()
			.stroke(.quaternary, lineWidth: 2)
		Circle()
			.trim(from: 0, to: progress)
			.stroke(
				tint,
				style: StrokeStyle(lineWidth: 2, lineCap: .round)
			)
			.rotationEffect(.degrees(-90))
		if let icon {
			Image(systemName: icon)
				.font(.system(size: 8, weight: .semibold))
				.foregroundStyle(.secondary)
		}
	}
	.frame(width: 18, height: 18)
}

@MainActor
@ViewBuilder
func podibleCoverView(url: URL?) -> some View {
	if let url {
		KFImage(url)
			.placeholder {
				podibleCoverPlaceholder()
			}
			.resizable()
			.scaledToFill()
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

private func podibleSanitizeFilename(_ value: String) -> String {
	let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
	if trimmed.isEmpty { return "book" }
	let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
	return trimmed.components(separatedBy: invalid).joined(separator: "-")
}

func podibleEpubURL(baseURLString: String, author: String, title: String)
	-> URL?
{
	let slug = podibleSlugify("\(author) \(title)")
	return PodibleClient(baseURLString: baseURLString).epubURL(slug: slug)
}

func podibleCoverURL(baseURLString: String, author: String, title: String)
	-> URL?
{
	let slug = podibleSlugify("\(author) \(title)")
	return PodibleClient(baseURLString: baseURLString).coverURL(slug: slug)
}

func lazyLibrarianAssetURL(baseURLString: String, path: String?) -> URL? {
	guard let path, let baseURL = URL(string: baseURLString) else { return nil }
	var base = baseURL
	if base.path.hasSuffix("/api") {
		base.deleteLastPathComponent()
	}
	if base.path.hasSuffix("/") == false {
		base.appendPathComponent("")
	}
	guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
		return nil
	}
	return url
}

private func podibleSlugify(_ value: String) -> String {
	let trimmed = value.lowercased().trimmingCharacters(
		in: .whitespacesAndNewlines
	)
	let dashed = trimmed.replacingOccurrences(
		of: "[^a-z0-9]+",
		with: "-",
		options: .regularExpression
	)
	let collapsed = dashed.replacingOccurrences(
		of: "-{2,}",
		with: "-",
		options: .regularExpression
	)
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
