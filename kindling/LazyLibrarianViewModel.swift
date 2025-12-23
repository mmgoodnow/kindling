import Foundation

@MainActor
final class LazyLibrarianViewModel: ObservableObject {
	struct DownloadProgress: Hashable {
		var ebook: Int
		var audiobook: Int
		var ebookFinished: Bool
		var audiobookFinished: Bool
		var ebookSeen: Bool
		var audiobookSeen: Bool
		var updatedAt: Date
	}

	@Published var query: String = ""
	@Published var searchResults: [LazyLibrarianBook] = []
	@Published var requests: [LazyLibrarianRequest] = []
	@Published var isLoading: Bool = false
	@Published var errorMessage: String?
	@Published var downloadProgressByBookID: [String: DownloadProgress] = [:]
	@Published private var pendingRequestsByID: [String: LazyLibrarianRequest] = [:]

	private var downloadPollingTasks: [String: Task<Void, Never>] = [:]
	private let downloadPollIntervalNanoseconds: UInt64 = 500_000_000
	private let searchCooldownInterval: TimeInterval = 20
	private var lastSearchByKey: [SearchCooldownKey: Date] = [:]

	private struct SearchCooldownKey: Hashable {
		let bookID: String
		let library: LazyLibrarianLibrary
	}

	deinit {
		for task in downloadPollingTasks.values {
			task.cancel()
		}
	}

	func loadRequests(using client: LazyLibrarianServing) async {
		isLoading = true
		errorMessage = nil
		do {
			var all = try await client.fetchRequests()
			var filteredAll = filtered(all)
			prunePendingRequests(matching: filteredAll)
			if needsCoverRefresh(all) {
				try? await client.fetchBookCovers(wait: true)
				all = try await client.fetchRequests()
				filteredAll = filtered(all)
				prunePendingRequests(matching: filteredAll)
			}
			let filteredRequests = mergePending(into: filteredAll)
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
			addPendingRequestIfNeeded(for: book)
			let requested = try await client.requestBook(id: book.id, titleHint: book.title, authorHint: book.author)
			if let pending = pendingRequestsByID[requested.id] {
				if requested.bookImagePath != nil {
					pendingRequestsByID[requested.id] = requested
				} else {
					pendingRequestsByID[requested.id] = pending
				}
			}
			markSearchTriggered(bookID: requested.id, library: .ebook)
			markSearchTriggered(bookID: requested.id, library: .audio)
			// Update the request list and the search results with the new status.
			if let existingIndex = requests.firstIndex(where: { $0.id == requested.id }) {
				let existing = requests[existingIndex]
				let updated = LazyLibrarianRequest(
					id: requested.id,
					title: requested.title,
					author: requested.author,
					status: requested.status,
					audioStatus: requested.audioStatus,
					bookAdded: requested.bookAdded ?? existing.bookAdded,
					bookLibrary: requested.bookLibrary ?? existing.bookLibrary,
					audioLibrary: requested.audioLibrary ?? existing.audioLibrary,
					bookImagePath: requested.bookImagePath ?? existing.bookImagePath
				)
				requests[existingIndex] = updated
			} else {
				requests.append(requested)
			}
			if let searchIndex = searchResults.firstIndex(where: { $0.id == requested.id }) {
				let updated = LazyLibrarianBook(
					id: requested.id,
					title: requested.title,
					author: requested.author,
					status: requested.status,
					audioStatus: requested.audioStatus,
					coverImageURL: searchResults[searchIndex].coverImageURL
				)
				searchResults[searchIndex] = updated
			}
			requests = filtered(requests)
			requests = mergePending(into: requests)
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
			markSearchTriggered(bookID: book.id, library: .ebook)
			markSearchTriggered(bookID: book.id, library: .audio)
		} catch {
			self.errorMessage = error.localizedDescription
		}
		isLoading = false
	}

	func triggerSearch(bookID: String, library: LazyLibrarianLibrary, using client: LazyLibrarianServing) async {
		guard canTriggerSearch(bookID: bookID, library: library) else { return }
		do {
			try await client.searchBook(id: bookID, library: library)
			markSearchTriggered(bookID: bookID, library: library)
		} catch {
			self.errorMessage = error.localizedDescription
		}
	}

	private func filtered(_ items: [LazyLibrarianRequest]) -> [LazyLibrarianRequest] {
		func isSkippedOrIgnored(_ status: LazyLibrarianRequestStatus?) -> Bool {
			guard let status else { return true }
			return status == .skipped || status == .ignored
		}
		let filtered = items.filter { item in
			!(isSkippedOrIgnored(item.status) && isSkippedOrIgnored(item.audioStatus))
		}
		return filtered.sorted { lhs, rhs in
			switch (lhs.bookAdded, rhs.bookAdded) {
			case let (l?, r?):
				if l != r { return l > r }
				return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
			case (_?, nil):
				return true
			case (nil, _?):
				return false
			case (nil, nil):
				return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
			}
		}
	}

	private func needsCoverRefresh(_ items: [LazyLibrarianRequest]) -> Bool {
		for item in items {
			let rawPath = item.bookImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
			if rawPath == nil || rawPath?.isEmpty == true {
				return true
			}
			let normalized = rawPath?.lowercased() ?? ""
			if normalized == "images/nocover.png" || normalized == "/images/nocover.png" {
				return true
			}
		}
		return false
	}

	func beginOptimisticRequest(for book: LazyLibrarianBook) {
		addPendingRequestIfNeeded(for: book)
	}

	private func addPendingRequestIfNeeded(for book: LazyLibrarianBook) {
		guard pendingRequestsByID[book.id] == nil else { return }
		if requests.contains(where: { $0.id == book.id }) { return }
		let coverPath = book.coverImageURL?.absoluteString ?? book.coverURL?.absoluteString
		let placeholder = LazyLibrarianRequest(
			id: book.id,
			title: book.title,
			author: book.author,
			status: .requested,
			audioStatus: .requested,
			bookAdded: .now,
			bookImagePath: coverPath
		)
		pendingRequestsByID[book.id] = placeholder
		requests.append(placeholder)
		requests = filtered(requests)
	}

	private func mergePending(into items: [LazyLibrarianRequest]) -> [LazyLibrarianRequest] {
		guard pendingRequestsByID.isEmpty == false else { return items }
		var merged = items
		for (id, pending) in pendingRequestsByID {
			guard merged.contains(where: { $0.id == id }) == false else {
				continue
			}
			merged.append(pending)
		}
		return filtered(merged)
	}

	private func prunePendingRequests(matching items: [LazyLibrarianRequest]) {
		guard pendingRequestsByID.isEmpty == false else { return }
		let existingIDs = Set(items.map(\.id))
		for id in existingIDs {
			pendingRequestsByID[id] = nil
		}
	}
	
    private func refreshRequestsSilently(using client: LazyLibrarianServing) async {
        do {
            let all = try await client.fetchRequests()
			let filteredAll = filtered(all)
			prunePendingRequests(matching: filteredAll)
            requests = mergePending(into: filteredAll)
        } catch {
            // Ignore transient errors; this is a silent refresh during polling.
        }
    }

	func shouldShowDownloadProgress(status: LazyLibrarianRequestStatus, audioStatus: LazyLibrarianRequestStatus?) -> Bool {
		isActive(status) || isActive(audioStatus)
	}

	func progressForBookID(_ id: String) -> DownloadProgress? {
		downloadProgressByBookID[id]
	}

	func shouldOfferSearch(status: LazyLibrarianRequestStatus?) -> Bool {
		isActive(status)
	}

	func canTriggerSearch(bookID: String, library: LazyLibrarianLibrary) -> Bool {
		let key = SearchCooldownKey(bookID: bookID, library: library)
		if let last = lastSearchByKey[key] {
			return Date.now.timeIntervalSince(last) >= searchCooldownInterval
		}
		return true
	}

	private func markSearchTriggered(bookID: String, library: LazyLibrarianLibrary) {
		lastSearchByKey[SearchCooldownKey(bookID: bookID, library: library)] = .now
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
				ebookSeen: false,
				audiobookSeen: false,
				updatedAt: .now
			)
		}

		downloadPollingTasks[bookID] = Task { [weak self] in
			guard let self else { return }
			let deadline = Date.now.addingTimeInterval(15 * 60)
            var lastStatusRefresh = Date.distantPast
            let statusRefreshInterval: TimeInterval = 3.0
			while Task.isCancelled == false, Date.now < deadline {
				do {
					let active = try await client.fetchDownloadProgress(limit: 50)
					self.mergeProgress(active, forBookID: bookID)
					// If both tracks are finished, do a final status refresh and continue polling statuses briefly until they settle.
					if let current = self.downloadProgressByBookID[bookID], current.ebookFinished, current.audiobookFinished {
                        await self.refreshRequestsSilently(using: client)
                        // Continue polling request statuses a bit longer until they settle to non-active, or timeout.
                        let settleDeadline = deadline
                        while Task.isCancelled == false, Date.now < settleDeadline {
                            if let req = self.requests.first(where: { $0.id == bookID }) {
                                if self.shouldShowDownloadProgress(status: req.status, audioStatus: req.audioStatus) == false {
                                    break
                                }
                            }
                            try? await Task.sleep(nanoseconds: self.downloadPollIntervalNanoseconds * 4)
                            await self.refreshRequestsSilently(using: client)
                        }
                        // Clear progress so UI hides bars once statuses settle.
                        self.downloadProgressByBookID[bookID] = nil
                        break
                    }
					// Periodically refresh request statuses to reflect transitions (e.g., Snatched -> Downloaded)
					if Date.now.timeIntervalSince(lastStatusRefresh) >= statusRefreshInterval {
						await self.refreshRequestsSilently(using: client)
						lastStatusRefresh = .now
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
			?? DownloadProgress(
				ebook: 0,
				audiobook: 0,
				ebookFinished: false,
				audiobookFinished: false,
				ebookSeen: false,
				audiobookSeen: false,
				updatedAt: .now
			)

		for item in items where item.bookID == bookID {
			let library = item.auxInfo
			let value = max(0, min(100, item.progress ?? 0))
			let finished = item.finished ?? (value >= 100)
			if library == LazyLibrarianLibrary.ebook.rawValue {
				current.ebook = value
				current.ebookFinished = finished
				current.ebookSeen = true
			} else if library == LazyLibrarianLibrary.audio.rawValue {
				current.audiobook = value
				current.audiobookFinished = finished
				current.audiobookSeen = true
			}
		}
		current.updatedAt = .now
		downloadProgressByBookID[bookID] = current
	}

	private func isActive(_ status: LazyLibrarianRequestStatus?) -> Bool {
		guard let status else { return false }
		switch status {
		case .requested, .wanted, .snatched, .seeding:
			return true
		case .downloaded, .failed, .have, .skipped, .open, .processed, .ignored, .okay, .unknown:
			return false
		}
	}
}
