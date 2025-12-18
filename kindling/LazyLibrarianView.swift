import SwiftUI

struct LazyLibrarianView: View {
	@EnvironmentObject var userSettings: UserSettings
	@StateObject private var viewModel = LazyLibrarianViewModel()
	@State private var isShowingSearchResults = false

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

	private func statusColor(_ status: LazyLibrarianRequestStatus) -> Color {
		lazyLibrarianStatusColor(status)
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
				.navigationTitle("Requests")
			}
		}
	}

	@ViewBuilder
	private func content(client: LazyLibrarianServing) -> some View {
		List {
			if let error = viewModel.errorMessage {
				Section {
					Text(error)
						.foregroundStyle(.red)
						.font(.caption)
				}
			}

			Section("Requests") {
				if viewModel.requests.isEmpty {
					Text("No requests yet.")
						.foregroundStyle(.secondary)
				} else {
					ForEach(viewModel.requests) { request in
						VStack(alignment: .leading, spacing: 8) {
							HStack(alignment: .center, spacing: 12) {
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
									statusPills(status: request.status, audioStatus: request.audioStatus)
										.lineLimit(1)
									if request.status == .wanted || request.audioStatus == .wanted {
										Button("Search") {
											Task {
												let book = LazyLibrarianBook(
													id: request.id,
													title: request.title,
													author: request.author,
													status: request.status,
													audioStatus: request.audioStatus
												)
												await viewModel.forceSearch(book, using: client)
											}
										}
										.buttonStyle(.bordered)
									}
								}
							}

							if viewModel.shouldShowDownloadProgress(status: request.status, audioStatus: request.audioStatus),
							   let progress = viewModel.progressForBookID(request.id) {
								downloadProgressBars(progress: progress)
							}
						}
						.padding(.vertical, 4)
					}
				}
			}
		}
		#if os(iOS)
			.listStyle(.insetGrouped)
	#else
			.listStyle(.inset)
	#endif
		.navigationTitle("Requests")
		.onAppear {
			Task { await viewModel.loadRequests(using: client) }
		}
		.searchable(text: $viewModel.query, prompt: "Search LazyLibrarian")
		.onSubmit(of: .search) {
			Task {
				await viewModel.search(using: client)
				isShowingSearchResults = true
			}
		}
		.navigationDestination(isPresented: $isShowingSearchResults) {
			LazyLibrarianSearchResultsView(viewModel: viewModel, client: client)
		}
	}

	@ViewBuilder
	private func statusPills(status: LazyLibrarianRequestStatus, audioStatus: LazyLibrarianRequestStatus?) -> some View {
		lazyLibrarianStatusPills(status: status, audioStatus: audioStatus)
	}

	@ViewBuilder
	private func downloadProgressBars(progress: LazyLibrarianViewModel.DownloadProgress) -> some View {
		lazyLibrarianDownloadProgressBars(progress: progress)
	}
}

private struct LazyLibrarianSearchResultsView: View {
	@ObservedObject var viewModel: LazyLibrarianViewModel
	let client: LazyLibrarianServing

	var body: some View {
		List {
			if let error = viewModel.errorMessage {
				Section {
					Text(error)
						.foregroundStyle(.red)
						.font(.caption)
				}
			}

			if viewModel.searchResults.isEmpty {
				ContentUnavailableView("No Results", systemImage: "magnifyingglass")
			} else {
				Section("Search Results") {
					ForEach(viewModel.searchResults) { book in
						VStack(alignment: .leading, spacing: 8) {
							HStack(alignment: .center, spacing: 12) {
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
									lazyLibrarianStatusPills(status: book.status, audioStatus: book.audioStatus)
										.lineLimit(1)
									Button {
										Task { await viewModel.request(book, using: client) }
									} label: {
										Text("GET")
									}
									.buttonStyle(.bordered)
									.controlSize(.small)
									.tint(.accentColor)
									.clipShape(Capsule())
									.disabled(book.status == .requested || book.status == .wanted)
								}
							}

							if viewModel.shouldShowDownloadProgress(status: book.status, audioStatus: book.audioStatus),
							   let progress = viewModel.progressForBookID(book.id) {
								lazyLibrarianDownloadProgressBars(progress: progress)
							}
						}
						.padding(.vertical, 4)
					}
				}
			}
		}
		#if os(iOS)
		.listStyle(.insetGrouped)
		#else
		.listStyle(.inset)
		#endif
		.navigationTitle("Search")
	}
}

fileprivate func lazyLibrarianStatusColor(_ status: LazyLibrarianRequestStatus) -> Color {
	switch status {
	case .downloaded: return .green
	case .snatched, .requested, .wanted, .seeding, .okay, .have: return .blue
	case .failed, .skipped, .ignored: return .red
	case .open, .processed: return .orange
	case .unknown: return .gray
	}
}

@ViewBuilder
fileprivate func lazyLibrarianStatusPills(status: LazyLibrarianRequestStatus, audioStatus: LazyLibrarianRequestStatus?) -> some View {
	if status == .open, let audioStatus, audioStatus == .open {
		EmptyView()
	} else {
		HStack(spacing: 8) {
			if status != .unknown {
				Label(status.rawValue, systemImage: "book.closed")
					.font(.caption)
					.foregroundStyle(lazyLibrarianStatusColor(status))
			}
			if let audioStatus, audioStatus != .unknown, audioStatus != status {
				Label(audioStatus.rawValue, systemImage: "headphones")
					.font(.caption)
					.foregroundStyle(lazyLibrarianStatusColor(audioStatus))
			}
		}
	}
}

@ViewBuilder
fileprivate func lazyLibrarianDownloadProgressBars(progress: LazyLibrarianViewModel.DownloadProgress) -> some View {
	VStack(alignment: .leading, spacing: 6) {
		HStack(spacing: 10) {
			Text("eBook")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.frame(width: 50, alignment: .leading)
			ProgressView(value: Double(progress.ebook), total: 100)
				.tint(progress.ebookFinished ? .green : .blue)
			Text("\(progress.ebook)%")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.frame(width: 40, alignment: .trailing)
		}
		HStack(spacing: 10) {
			Text("Audio")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.frame(width: 50, alignment: .leading)
			ProgressView(value: Double(progress.audiobook), total: 100)
				.tint(progress.audiobookFinished ? .green : .blue)
			Text("\(progress.audiobook)%")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.frame(width: 40, alignment: .trailing)
		}
	}
}

#Preview {
	NavigationStack {
		LazyLibrarianView(client: LazyLibrarianMockClient())
			.environmentObject(UserSettings())
	}
}
