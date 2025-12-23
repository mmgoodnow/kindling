import SwiftUI

struct LazyLibrarianSearchResultsView: View {
	@ObservedObject var viewModel: LazyLibrarianViewModel
	@EnvironmentObject var userSettings: UserSettings
	let client: LazyLibrarianServing
	@State private var pendingRequestIDs: Set<String> = []

	var body: some View {
		List {
			if let error = viewModel.errorMessage {
				Text(error)
					.foregroundStyle(.red)
					.font(.caption)
			}

			if viewModel.searchResults.isEmpty {
				ContentUnavailableView(
					"No Results",
					systemImage: "magnifyingglass"
				)
			} else {
				ForEach(viewModel.searchResults) { book in
					searchRow(for: book)
				}
			}
		}
		.navigationTitle("Search")
	}

	private func searchRow(for book: LazyLibrarianBook) -> some View {
		let isPending =
			pendingRequestIDs.contains(book.id)
			&& viewModel.progressForBookID(book.id) == nil
		let progress = viewModel.progressForBookID(book.id)
		let matchingRequest = viewModel.requests.first(where: { $0.id == book.id })
		let effectiveRequest = matchingRequest
			?? (isPending
				? LazyLibrarianRequest(
					id: book.id,
					title: book.title,
					author: book.author,
					status: .requested,
					audioStatus: .requested,
					bookAdded: .now
				)
				: nil)
		let shouldShowGetButton = effectiveRequest == nil

		return
			VStack(alignment: .leading, spacing: 8) {
				HStack(alignment: .center, spacing: 8) {
					podibleCoverView(
						url: book.coverImageURL
							?? podibleCoverURL(
								baseURLString: userSettings.podibleURL,
								author: book.author,
								title: book.title
							)
					)
					VStack(alignment: .leading, spacing: 4) {
						Text(book.title)
							.font(.headline)
							.lineLimit(2)
						Text(book.author)
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					Spacer(minLength: 8)
					VStack(alignment: .trailing, spacing: 6) {
						if let request = effectiveRequest {
							lazyLibrarianStatusCluster(
								request: request,
								progress: progress,
								canTriggerSearch: { library in
									viewModel.canTriggerSearch(
										bookID: request.id,
										library: library
									)
								},
								shouldOfferSearch: { status in
									viewModel.shouldOfferSearch(status: status)
								},
								triggerSearch: { library in
									Task {
										await viewModel.triggerSearch(
											bookID: request.id,
											library: library,
											using: client
										)
									}
								},
								downloadAction: {},
								canDownload: false
							)
						} else if shouldShowGetButton {
							Group {
								if isPending {
									Button {
										Task {
											await viewModel.request(
												book,
												using: client
											)
										}
									} label: {
										Text("GET")
									}
									.buttonStyle(.bordered)
									.foregroundStyle(.secondary)
								} else {
									Button {
										pendingRequestIDs.insert(book.id)
										viewModel.beginOptimisticRequest(for: book)
										Task {
											await viewModel.request(
												book,
												using: client
											)
											let updated = viewModel
												.searchResults
												.first(where: {
													$0.id == book.id
												})
											let shouldWait =
												updated.map {
													viewModel
														.shouldShowDownloadProgress(
															status: $0.status,
															audioStatus: $0
																.audioStatus
														)
												} ?? false
											if shouldWait == false
												|| viewModel.progressForBookID(
													book.id
												) != nil
											{
												pendingRequestIDs.remove(
													book.id
												)
											}
										}
									} label: {
										Text("GET")
									}
									.buttonStyle(.bordered)
								}
							}
							.controlSize(.small)
							.tint(.accentColor)
							.clipShape(Capsule())
							.disabled(
								isPending || book.status == .requested
									|| book.status == .wanted
							)
						}
					}
				}
			}
			.onChange(of: viewModel.progressForBookID(book.id)?.updatedAt) { _, _ in
				pendingRequestIDs.remove(book.id)
			}
	}
}

#Preview {
	let viewModel = LazyLibrarianViewModel()
	viewModel.searchResults = [
		LazyLibrarianBook(
			id: "1",
			title: "They Both Die at the End",
			author: "Adam Silvera",
			status: .requested,
			audioStatus: .requested,
			coverImageURL: URL(
				string:
					"https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1315601232l/11869272._SX98_.jpg"
			)
		),
		LazyLibrarianBook(
			id: "2",
			title: "The Secret History",
			author: "Donna Tartt",
			status: .unknown
		),
	]
	viewModel.downloadProgressByBookID["1"] =
		LazyLibrarianViewModel.DownloadProgress(
			ebook: 42,
			audiobook: 18,
			ebookFinished: false,
			audiobookFinished: false,
			ebookSeen: true,
			audiobookSeen: true,
			updatedAt: .now
		)

	return NavigationStack {
		LazyLibrarianSearchResultsView(
			viewModel: viewModel,
			client: LazyLibrarianMockClient()
		)
		.environmentObject(UserSettings())
	}
}
