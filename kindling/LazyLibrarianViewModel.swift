import Foundation

@MainActor
final class LazyLibrarianViewModel: ObservableObject {
	struct DownloadProgress: Hashable {
		var ebook: Int
		var audiobook: Int
		var ebookFinished: Bool
		var audiobookFinished: Bool
		var updatedAt: Date
	}

	@Published var query: String = ""
	@Published var searchResults: [LazyLibrarianBook] = []
	@Published var requests: [LazyLibrarianRequest] = []
	@Published var isLoading: Bool = false
	@Published var errorMessage: String?
	@Published var downloadProgressByBookID: [String: DownloadProgress] = [:]

	private var downloadPollingTasks: [String: Task<Void, Never>] = [:]
	private let downloadPollIntervalNanoseconds: UInt64 = 500_000_000

	deinit {
		for task in downloadPollingTasks.values {
			task.cancel()
		}
	}

	func loadRequests(using client: LazyLibrarianServing) async {
		isLoading = true
		errorMessage = nil
		do {
			let all = try await client.fetchRequests()
			let filteredRequests = filtered(all)
			requests = filteredRequests
			startPollingIfNeeded(for: filteredRequests, client: client)
		} catch {
			errorMessage = error.localizedDescription
		}
		isLoading = false
	}

	func search(using client: LazyLibrarianServing) async {
		guard query.isEmpty == false else { return }
		isLoading = true
		errorMessage = nil
		do {
			searchResults = try await client.searchBooks(query: query)
		} catch {
			errorMessage = error.localizedDescription
		}
		isLoading = false
	}

	func request(_ book: LazyLibrarianBook, using client: LazyLibrarianServing) async {
		isLoading = true
		errorMessage = nil
		do {
			let requested = try await client.requestBook(id: book.id, titleHint: book.title, authorHint: book.author)
			// Update the request list and the search results with the new status.
			if let existingIndex = requests.firstIndex(where: { $0.id == requested.id }) {
				requests[existingIndex] = requested
			} else {
				requests.append(requested)
			}
			if let searchIndex = searchResults.firstIndex(where: { $0.id == requested.id }) {
				let updated = LazyLibrarianBook(
					id: requested.id,
					title: requested.title,
					author: requested.author,
					status: requested.status,
					audioStatus: requested.audioStatus
				)
				searchResults[searchIndex] = updated
			}
			requests = filtered(requests)
			startPolling(bookID: requested.id, client: client)
		} catch {
			self.errorMessage = error.localizedDescription
			print("[LazyLibrarian] request error for \(book.id): \(error.localizedDescription)")
		}
		isLoading = false
	}

	func forceSearch(_ book: LazyLibrarianBook, using client: LazyLibrarianServing) async {
		isLoading = true
		errorMessage = nil
		do {
			try await client.searchBook(id: book.id, library: .ebook)
			try await client.searchBook(id: book.id, library: .audio)
		} catch {
			self.errorMessage = error.localizedDescription
		}
		isLoading = false
	}

	private func filtered(_ items: [LazyLibrarianRequest]) -> [LazyLibrarianRequest] {
		func isSkippedOrIgnored(_ status: LazyLibrarianRequestStatus?) -> Bool {
			guard let status else { return true }
			return status == .skipped || status == .ignored
		}
		return items.filter { item in
			!(isSkippedOrIgnored(item.status) && isSkippedOrIgnored(item.audioStatus))
		}
	}

	func shouldShowDownloadProgress(status: LazyLibrarianRequestStatus, audioStatus: LazyLibrarianRequestStatus?) -> Bool {
		func isActive(_ s: LazyLibrarianRequestStatus?) -> Bool {
			guard let s else { return false }
			switch s {
			case .requested, .wanted, .snatched, .seeding:
				return true
			case .downloaded, .failed, .have, .skipped, .open, .processed, .ignored, .okay, .unknown:
				return false
			}
		}
		return isActive(status) || isActive(audioStatus)
	}

	func progressForBookID(_ id: String) -> DownloadProgress? {
		downloadProgressByBookID[id]
	}

	private func startPollingIfNeeded(for items: [LazyLibrarianRequest], client: LazyLibrarianServing) {
		for item in items where shouldShowDownloadProgress(status: item.status, audioStatus: item.audioStatus) {
			startPolling(bookID: item.id, client: client)
		}
	}

	private func startPolling(bookID: String, client: LazyLibrarianServing) {
		if let existing = downloadPollingTasks[bookID] {
			existing.cancel()
			downloadPollingTasks[bookID] = nil
		}

		if downloadProgressByBookID[bookID] == nil {
			downloadProgressByBookID[bookID] = DownloadProgress(
				ebook: 0,
				audiobook: 0,
				ebookFinished: false,
				audiobookFinished: false,
				updatedAt: .now
			)
		}

		downloadPollingTasks[bookID] = Task { [weak self] in
			guard let self else { return }
			let deadline = Date.now.addingTimeInterval(15 * 60)
			while Task.isCancelled == false, Date.now < deadline {
				do {
					let active = try await client.fetchDownloadProgress(limit: 50)
					self.mergeProgress(active, forBookID: bookID)
					if let current = self.downloadProgressByBookID[bookID], current.ebookFinished, current.audiobookFinished {
						break
					}
				} catch {
					// Keep polling; transient failures are expected while downloads are being created.
				}

				try? await Task.sleep(nanoseconds: self.downloadPollIntervalNanoseconds)
			}
			self.downloadPollingTasks[bookID] = nil
		}
	}

	private func mergeProgress(_ items: [LazyLibrarianDownloadProgressItem], forBookID bookID: String) {
		var current = downloadProgressByBookID[bookID]
			?? DownloadProgress(ebook: 0, audiobook: 0, ebookFinished: false, audiobookFinished: false, updatedAt: .now)

		for item in items where item.bookID == bookID {
			let library = item.auxInfo
			let value = max(0, min(100, item.progress ?? 0))
			let finished = item.finished ?? (value >= 100)
			if library == LazyLibrarianLibrary.ebook.rawValue {
				current.ebook = value
				current.ebookFinished = finished
			} else if library == LazyLibrarianLibrary.audio.rawValue {
				current.audiobook = value
				current.audiobookFinished = finished
			}
		}
		current.updatedAt = .now
		downloadProgressByBookID[bookID] = current
	}
}
