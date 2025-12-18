import Foundation

enum LazyLibrarianError: LocalizedError {
	case notConfigured
	case badURL
	case badResponse
	case server(String)
	case api(String)
	case unsupported(String)

	var errorDescription: String? {
		switch self {
		case .notConfigured:
			return "LazyLibrarian is not configured."
		case .badURL:
			return "The LazyLibrarian URL looks invalid."
		case .badResponse:
			return "Could not parse LazyLibrarian's response."
		case .server(let message):
			return message
		case .api(let message):
			return message
		case .unsupported(let message):
			return message
		}
	}
}

enum LazyLibrarianRequestStatus: String, Decodable {
	case requested = "Requested"
	case wanted = "Wanted"
	case snatched = "Snatched"
	case seeding = "Seeding"
	case downloaded = "Downloaded"
	case failed = "Failed"
	case have = "Have"
	case skipped = "Skipped"
	case open = "Open"
	case processed = "Processed"
	case ignored = "Ignored"
	case okay = "OK"
	case unknown = "Unknown"

	init(from decoder: Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = LazyLibrarianRequestStatus(rawValue: raw) ?? .unknown
	}

	var isComplete: Bool {
		switch self {
		case .downloaded, .have, .open, .processed:
			return true
		default:
			return false
		}
	}
}

struct LazyLibrarianBook: Identifiable, Hashable, Decodable {
	let id: String
	let title: String
	let author: String
	let status: LazyLibrarianRequestStatus
	let audioStatus: LazyLibrarianRequestStatus?
	let coverURL: URL?
	let rating: Double?
	let ratingCount: Int?
	let published: String?
	let link: URL?

	init(
		id: String, title: String, author: String, status: LazyLibrarianRequestStatus,
		audioStatus: LazyLibrarianRequestStatus? = nil,
		coverURL: URL? = nil, rating: Double? = nil, ratingCount: Int? = nil,
		published: String? = nil, link: URL? = nil
	) {
		self.id = id
		self.title = title
		self.author = author
		self.status = status
		self.audioStatus = audioStatus
		self.coverURL = coverURL
		self.rating = rating
		self.ratingCount = ratingCount
		self.published = published
		self.link = link
	}

	private enum CodingKeys: String, CodingKey {
		case idLower = "bookid"
		case idUpper = "BookID"
		case idPlain = "id"
		case titleLower = "bookname"
		case titleUpper = "BookName"
		case authorLower = "authorname"
		case authorUpper = "AuthorName"
		case statusAlt = "Status"
		case status = "status"
		case audioStatus = "AudioStatus"
		case coverURL = "cover"
		case rating = "bookrate"
		case ratingCountLower = "bookrate_count"
		case ratingCountUpper = "BookRate"
		case publishedLower = "bookdate"
		case publishedUpper = "BookDate"
		case link = "booklink"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(String.self, forKeys: [.idLower, .idUpper, .idPlain])
		title = try container.decodeIfPresent(String.self, forKeys: [.titleLower, .titleUpper])
		author = try container.decodeIfPresent(String.self, forKeys: [.authorLower, .authorUpper])
		status = (try? container.decode(LazyLibrarianRequestStatus.self, forKey: .status))
			?? (try? container.decode(LazyLibrarianRequestStatus.self, forKey: .statusAlt))
			?? (try? container.decode(LazyLibrarianRequestStatus.self, forKey: .audioStatus))
			?? .unknown
		audioStatus = (try? container.decode(LazyLibrarianRequestStatus.self, forKey: .audioStatus))
		coverURL = try? container.decodeIfPresent(URL.self, forKey: .coverURL)
		rating = try? container.decodeIfPresent(Double.self, forKey: .rating)
		ratingCount =
			(try? container.decodeIfPresent(Int.self, forKey: .ratingCountLower))
			?? (try? container.decodeIfPresent(Int.self, forKey: .ratingCountUpper))
		published =
			(try? container.decodeIfPresent(String.self, forKey: .publishedLower))
			?? (try? container.decodeIfPresent(String.self, forKey: .publishedUpper))
		link = try? container.decodeIfPresent(URL.self, forKey: .link)
	}
}

struct LazyLibrarianRequest: Identifiable, Hashable, Decodable {
	let id: String
	let title: String
	let author: String
	let status: LazyLibrarianRequestStatus
	let audioStatus: LazyLibrarianRequestStatus?

	init(id: String, title: String, author: String, status: LazyLibrarianRequestStatus, audioStatus: LazyLibrarianRequestStatus? = nil) {
		self.id = id
		self.title = title
		self.author = author
		self.status = status
		self.audioStatus = audioStatus
	}

	private enum CodingKeys: String, CodingKey {
		case idLower = "bookid"
		case idUpper = "BookID"
		case idPlain = "id"
		case titleLower = "bookname"
		case titleUpper = "BookName"
		case authorLower = "authorname"
		case authorUpper = "AuthorName"
		case status = "status"
		case statusAlt = "Status"
		case audioStatus = "AudioStatus"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(String.self, forKeys: [.idLower, .idUpper, .idPlain])
		title = try container.decodeIfPresent(String.self, forKeys: [.titleLower, .titleUpper])
		author = try container.decodeIfPresent(String.self, forKeys: [.authorLower, .authorUpper])
		status = (try? container.decode(LazyLibrarianRequestStatus.self, forKey: .status))
			?? (try? container.decode(LazyLibrarianRequestStatus.self, forKey: .statusAlt))
			?? (try? container.decode(LazyLibrarianRequestStatus.self, forKey: .audioStatus))
			?? .unknown
		audioStatus = (try? container.decode(LazyLibrarianRequestStatus.self, forKey: .audioStatus))
	}
}

private extension KeyedDecodingContainer {
	func decodeIfPresent(_ type: String.Type, forKeys keys: [Key]) throws -> String {
		for key in keys {
			if let value = try decodeIfPresent(type, forKey: key) {
				return value
			}
		}
		throw LazyLibrarianError.badResponse
	}
}

protocol LazyLibrarianServing {
	func searchBooks(query: String) async throws -> [LazyLibrarianBook]
	func requestBook(id: String, titleHint: String?, authorHint: String?) async throws -> LazyLibrarianRequest
	func fetchRequests() async throws -> [LazyLibrarianRequest]
	func searchBook(id: String, library: LazyLibrarianLibrary) async throws
	func fetchDownloadProgress(limit: Int?) async throws -> [LazyLibrarianDownloadProgressItem]
}

enum LazyLibrarianLibrary: String {
	case ebook = "eBook"
	case audio = "AudioBook"
}

struct LazyLibrarianDownloadProgressItem: Hashable, Decodable {
	let bookID: String?
	let auxInfo: String?
	let source: String?
	let downloadID: String?
	let progress: Int?
	let finished: Bool?

	init(bookID: String?, auxInfo: String?, source: String?, downloadID: String?, progress: Int?, finished: Bool?) {
		self.bookID = bookID
		self.auxInfo = auxInfo
		self.source = source
		self.downloadID = downloadID
		self.progress = progress
		self.finished = finished
	}

	private enum CodingKeys: String, CodingKey {
		case bookIDUpper = "BookID"
		case bookIDLower = "bookid"
		case auxInfo = "AuxInfo"
		case sourceUpper = "Source"
		case sourceLower = "source"
		case downloadIDUpper = "DownloadID"
		case downloadIDLower = "downloadid"
		case progress
		case finished
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		bookID =
			(try? container.decodeIfPresent(String.self, forKey: .bookIDUpper))
			?? (try? container.decodeIfPresent(String.self, forKey: .bookIDLower))
		auxInfo = try? container.decodeIfPresent(String.self, forKey: .auxInfo)
		source =
			(try? container.decodeIfPresent(String.self, forKey: .sourceUpper))
			?? (try? container.decodeIfPresent(String.self, forKey: .sourceLower))
		downloadID =
			(try? container.decodeIfPresent(String.self, forKey: .downloadIDUpper))
			?? (try? container.decodeIfPresent(String.self, forKey: .downloadIDLower))
		progress = try? container.decodeIfPresent(Int.self, forKey: .progress)
		finished = try? container.decodeIfPresent(Bool.self, forKey: .finished)
	}
}

struct LazyLibrarianClient: LazyLibrarianServing {
	let baseURL: URL
	let apiKey: String
	var session: URLSession = .shared

	#if DEBUG
	private func logResponse(_ label: String, data: Data) {
		if let str = String(data: data, encoding: .utf8) {
			let prefix = str.count > 500 ? String(str.prefix(500)) + "…" : str
			print("[LazyLibrarian] \(label): \(prefix)")
		} else {
			print("[LazyLibrarian] \(label): <non-utf8 data \(data.count) bytes>")
		}
	}
	#endif

	private func apiURL(cmd: String, queryItems: [URLQueryItem]) -> URL? {
		var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
		let basePath = components?.path ?? ""
		if basePath.hasSuffix("/api") == false {
			components?.path = basePath.appending("/api")
		}
		var items = [URLQueryItem(name: "apikey", value: apiKey),
		             URLQueryItem(name: "cmd", value: cmd)]
		items.append(contentsOf: queryItems)
		components?.queryItems = items
		return components?.url
	}

	private func decodeBooks(from data: Data) throws -> [LazyLibrarianBook] {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase

		struct APIError: Decodable {
			let code: Int?
			let message: String?
		}
		struct APIEnvelope: Decodable {
			let success: Bool?
			let data: [LazyLibrarianBook]?
			let error: APIError?
			let books: [LazyLibrarianBook]?
		}
		// Common shapes: { "books": [...] } or raw array
		struct Envelope: Decodable { let books: [LazyLibrarianBook]? }

		if let wrapper = try? decoder.decode(APIEnvelope.self, from: data) {
			if let success = wrapper.success, success == false {
				throw LazyLibrarianError.api(wrapper.error?.message ?? "LazyLibrarian error")
			}
			if let books = wrapper.data ?? wrapper.books {
				return books
			}
		}

		if let envelope = try? decoder.decode(Envelope.self, from: data), let books = envelope.books {
			return books
		}
		if let books = try? decoder.decode([LazyLibrarianBook].self, from: data) {
			return books
		}
		// Last-resort: attempt to decode { "data": [...] }
		struct Alt: Decodable { let data: [LazyLibrarianBook]? }
		if let alt = try? decoder.decode(Alt.self, from: data), let books = alt.data {
			return books
		}

		throw LazyLibrarianError.badResponse
	}

	private func decodeRequests(from data: Data) throws -> [LazyLibrarianRequest] {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .useDefaultKeys

		struct APIError: Decodable {
			let code: Int?
			let message: String?
		}
		struct APIEnvelope: Decodable {
			let success: Bool?
			let data: [LazyLibrarianRequest]?
			let error: APIError?
			let books: [LazyLibrarianRequest]?
			let requests: [LazyLibrarianRequest]?
		}

		struct Envelope: Decodable {
			let requests: [LazyLibrarianRequest]?
			let books: [LazyLibrarianRequest]?
			let data: [LazyLibrarianRequest]?
		}

		if let wrapper = try? decoder.decode(APIEnvelope.self, from: data) {
			if let success = wrapper.success, success == false {
				throw LazyLibrarianError.api(wrapper.error?.message ?? "LazyLibrarian error")
			}
			if let reqs = wrapper.data ?? wrapper.requests ?? wrapper.books {
				return reqs
			}
		}

		if let envelope = try? decoder.decode(Envelope.self, from: data) {
			if let requests = envelope.requests ?? envelope.books ?? envelope.data {
				return requests
			}
		}
		if let requests = try? decoder.decode([LazyLibrarianRequest].self, from: data) {
			return requests
		}
		throw LazyLibrarianError.badResponse
	}

	private func queueBookWithBackoff(id: String, library: LazyLibrarianLibrary, titleHint: String?, authorHint: String?, maxAttempts: Int = 5, initialDelayMS: UInt64 = 400) async throws -> LazyLibrarianRequest {
		var attempt = 1
		var delay = initialDelayMS
		while true {
			#if DEBUG
			print("[LazyLibrarian] queueBook attempt=\(attempt) id=\(id) type=\(library.rawValue)")
			#endif
			do {
				let result = try await queueBook(id: id, library: library, titleHint: titleHint, authorHint: authorHint)
				#if DEBUG
				print("[LazyLibrarian] queueBook attempt=\(attempt) id=\(id) type=\(library.rawValue) succeeded")
				#endif
				return result
			} catch {
				let message = error.localizedDescription.lowercased()
				let isInvalidID = message.contains("invalid id")
				if attempt >= maxAttempts || isInvalidID == false {
					throw error
				}
				#if DEBUG
				print("[LazyLibrarian] queueBook backoff sleep start id=\(id) type=\(library.rawValue) duration=\(delay)ms")
				#endif
				try? await Task.sleep(nanoseconds: delay * 1_000_000)
				#if DEBUG
				print("[LazyLibrarian] queueBook backoff sleep done id=\(id) type=\(library.rawValue)")
				#endif
				delay = delay * 2
				attempt += 1
			}
		}
	}

    func searchBooks(query: String) async throws -> [LazyLibrarianBook] {
        // LL supports findBook via GoodReads/GoogleBooks
        guard let url = apiURL(cmd: "findBook", queryItems: [
            URLQueryItem(name: "name", value: query)
        ]) else {
            throw LazyLibrarianError.badURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LazyLibrarianError.badResponse
        }
        do {
            return try decodeBooks(from: data)
        } catch {
            #if DEBUG
            logResponse("booksearch decode failed", data: data)
            #endif
            throw error
        }
    }

	func requestBook(id: String, titleHint: String? = nil, authorHint: String? = nil) async throws -> LazyLibrarianRequest {
		#if DEBUG
		print("[LazyLibrarian] requestBook start id=\(id) title=\(titleHint ?? "") author=\(authorHint ?? "")")
		#endif

		// Add book first
		#if DEBUG
		print("[LazyLibrarian] addBookIfNeeded id=\(id)")
		#endif
		try await addBookIfNeeded(id: id)

		#if DEBUG
		print("[LazyLibrarian] requestBook initial sleep start 2000ms id=\(id)")
		#endif
		// Give LL time to persist new author/book records
		try? await Task.sleep(nanoseconds: 2_000_000_000)
		#if DEBUG
		print("[LazyLibrarian] requestBook initial sleep done id=\(id)")
		#endif

		// Queue with targeted retries on "Invalid id"
		let ebookResult = try await queueBookWithBackoff(id: id, library: .ebook, titleHint: titleHint, authorHint: authorHint)
		let audioResult = try await queueBookWithBackoff(id: id, library: .audio, titleHint: titleHint, authorHint: authorHint)

		// Fire-and-forget searches (non-fatal)
		#if DEBUG
		print("[LazyLibrarian] searchBook eBook id=\(id)")
		#endif
		try? await searchBook(id: id, library: .ebook)
		#if DEBUG
		print("[LazyLibrarian] searchBook AudioBook id=\(id)")
		#endif
		try? await searchBook(id: id, library: .audio)

		#if DEBUG
		print("[LazyLibrarian] requestBook done id=\(id) -> status(eBook)=\(ebookResult.status.rawValue) status(Audio)=\(audioResult.status.rawValue)")
		#endif

		return LazyLibrarianRequest(
			id: ebookResult.id,
			title: ebookResult.title,
			author: ebookResult.author,
			status: ebookResult.status,
			audioStatus: audioResult.status
		)
	}

	private func addBookIfNeeded(id: String) async throws {
		guard let url = apiURL(
			cmd: "addBook",
			queryItems: [URLQueryItem(name: "id", value: id)]
		) else {
			throw LazyLibrarianError.badURL
		}
		let (data, response) = try await session.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw LazyLibrarianError.badResponse
		}
		#if DEBUG
		if let str = String(data: data, encoding: .utf8) {
			let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmed.isEmpty == false {
				print("[LazyLibrarian] addBook response: \(trimmed)")
			}
		}
		#endif
	}

	private func queueBook(id: String, library: LazyLibrarianLibrary, titleHint: String?, authorHint: String?) async throws -> LazyLibrarianRequest {
		guard let url = apiURL(
			cmd: "queueBook",
			queryItems: [
				URLQueryItem(name: "id", value: id),
				URLQueryItem(name: "type", value: library.rawValue)
			]
		) else {
			throw LazyLibrarianError.badURL
		}
		let (data, response) = try await session.data(from: url)

		#if DEBUG
		print("[LazyLibrarian] queueBook response id=\(id) type=\(library.rawValue) status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
		#endif

		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			#if DEBUG
			logResponse("requestBook bad status \( (response as? HTTPURLResponse)?.statusCode ?? -1)", data: data)
			#endif
			throw LazyLibrarianError.badResponse
		}

		// The request response often echoes the book info; fall back to a generic response.
		do {
			let decoder = JSONDecoder()
			decoder.keyDecodingStrategy = .convertFromSnakeCase
			if let wrapper = try? decoder.decode(APIResponseWrapper<LazyLibrarianRequest>.self, from: data) {
				if let success = wrapper.success, success == false {
					throw LazyLibrarianError.api(wrapper.error?.message ?? "LazyLibrarian error")
				}
				if let result = wrapper.data {
					return result
				}
			}
			if let requested = try? decoder.decode(LazyLibrarianRequest.self, from: data) {
				return requested
			}
			if let requests = try? decodeRequests(from: data), let first = requests.first(where: { $0.id == id }) {
				return first
			}
		} catch {
			#if DEBUG
			logResponse("queueBook decode failed id=\(id) type=\(library.rawValue)", data: data)
			#endif
			throw error
		}

		if let raw = String(data: data, encoding: .utf8) {
			let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
			#if DEBUG
			print("[LazyLibrarian] queueBook raw id=\(id) type=\(library.rawValue) body=\(trimmed)")
			#endif
			if trimmed.uppercased() == "OK" {
				return LazyLibrarianRequest(
					id: id,
					title: titleHint ?? "Book \(id)",
					author: authorHint ?? "",
					status: library == .ebook ? .requested : .unknown,
					audioStatus: library == .audio ? .requested : nil
				)
			}
			if trimmed.lowercased().contains("invalid id") {
				throw LazyLibrarianError.server(trimmed)
			}
			#if DEBUG
			logResponse("queueBook unsupported response id=\(id) type=\(library.rawValue)", data: data)
			#endif
		}

		throw LazyLibrarianError.badResponse
	}

	func fetchRequests() async throws -> [LazyLibrarianRequest] {
		// getAllBooks gives us current library + statuses so the list isn't empty on launch.
		guard let url = apiURL(cmd: "getAllBooks", queryItems: []) else {
			throw LazyLibrarianError.badURL
		}
		let (data, response) = try await session.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw LazyLibrarianError.badResponse
		}
		do {
			return try decodeRequests(from: data)
		} catch {
			#if DEBUG
			logResponse("getrequests decode failed", data: data)
			#endif
			throw error
		}
	}

	func searchBook(id: String, library: LazyLibrarianLibrary) async throws {
		let typeItem = URLQueryItem(name: "type", value: library.rawValue)
		guard let url = apiURL(cmd: "searchBook", queryItems: [
			URLQueryItem(name: "id", value: id),
			typeItem
		]) else {
			throw LazyLibrarianError.badURL
		}
		#if DEBUG
		print("[LazyLibrarian] searchBook call id=\(id) type=\(library.rawValue)")
		#endif
		let (data, response) = try await session.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			#if DEBUG
			logResponse("searchBook bad status id=\(id) type=\(library.rawValue) \((response as? HTTPURLResponse)?.statusCode ?? -1)", data: data)
			#endif
			throw LazyLibrarianError.badResponse
		}
		#if DEBUG
		logResponse("searchBook \(library.rawValue)", data: data)
		#endif
	}

	func fetchDownloadProgress(limit: Int? = nil) async throws -> [LazyLibrarianDownloadProgressItem] {
		var items: [URLQueryItem] = []
		if let limit {
			items.append(URLQueryItem(name: "limit", value: String(limit)))
		}
		guard let url = apiURL(cmd: "getDownloadProgress", queryItems: items) else {
			throw LazyLibrarianError.badURL
		}
		let (data, response) = try await session.data(from: url)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw LazyLibrarianError.badResponse
		}

		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase

		struct PascalError: Decodable {
			let code: Int?
			let message: String?
			private enum CodingKeys: String, CodingKey { case code = "Code", message = "Message" }
		}
		struct PascalWrapperArray: Decodable {
			let success: Bool?
			let data: [LazyLibrarianDownloadProgressItem]?
			let error: PascalError?
			private enum CodingKeys: String, CodingKey { case success = "Success", data = "Data", error = "Error" }
		}
		struct PascalWrapperSingle: Decodable {
			let success: Bool?
			let data: LazyLibrarianDownloadProgressItem?
			let error: PascalError?
			private enum CodingKeys: String, CodingKey { case success = "Success", data = "Data", error = "Error" }
		}

		if let wrapper = try? decoder.decode(PascalWrapperArray.self, from: data) {
			if let success = wrapper.success, success == false {
				throw LazyLibrarianError.api(wrapper.error?.message ?? "LazyLibrarian error")
			}
			if let result = wrapper.data {
				return result
			}
		}

		if let wrapper = try? decoder.decode(PascalWrapperSingle.self, from: data) {
			if let success = wrapper.success, success == false {
				throw LazyLibrarianError.api(wrapper.error?.message ?? "LazyLibrarian error")
			}
			if let single = wrapper.data {
				return [single]
			}
		}

		if let raw = try? decoder.decode([LazyLibrarianDownloadProgressItem].self, from: data) {
			return raw
		}

		#if DEBUG
		logResponse("getDownloadProgress decode failed", data: data)
		#endif
		throw LazyLibrarianError.badResponse
	}

	private struct APIResponseWrapper<T: Decodable>: Decodable {
		let success: Bool?
		let data: T?
		let error: APIError?

		struct APIError: Decodable {
			let code: Int?
			let message: String?

			private enum CodingKeys: String, CodingKey {
				case codeLower = "code"
				case messageLower = "message"
				case codeUpper = "Code"
				case messageUpper = "Message"
			}

			init(from decoder: Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				code =
					(try? container.decodeIfPresent(Int.self, forKey: .codeLower))
					?? (try? container.decodeIfPresent(Int.self, forKey: .codeUpper))
				message =
					(try? container.decodeIfPresent(String.self, forKey: .messageLower))
					?? (try? container.decodeIfPresent(String.self, forKey: .messageUpper))
			}
		}

		private enum CodingKeys: String, CodingKey {
			case successLower = "success"
			case dataLower = "data"
			case errorLower = "error"
			case successUpper = "Success"
			case dataUpper = "Data"
			case errorUpper = "Error"
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			success =
				(try? container.decodeIfPresent(Bool.self, forKey: .successLower))
				?? (try? container.decodeIfPresent(Bool.self, forKey: .successUpper))
			data =
				(try? container.decodeIfPresent(T.self, forKey: .dataLower))
				?? (try? container.decodeIfPresent(T.self, forKey: .dataUpper))
			error =
				(try? container.decodeIfPresent(APIError.self, forKey: .errorLower))
				?? (try? container.decodeIfPresent(APIError.self, forKey: .errorUpper))
		}
	}
}

// Preview/testing helper that simulates LazyLibrarian without network calls.
final actor LazyLibrarianMockClient: LazyLibrarianServing {
	private var requests: [LazyLibrarianRequest] = [
		LazyLibrarianRequest(id: "1", title: "Project Hail Mary", author: "Andy Weir", status: .downloaded),
		LazyLibrarianRequest(id: "2", title: "The City We Became", author: "N. K. Jemisin", status: .requested),
	]
	private var progress: [String: (ebook: Int, audio: Int)] = [:]

	func searchBooks(query: String) async throws -> [LazyLibrarianBook] {
		let canned = [
			LazyLibrarianBook(id: "1", title: "Project Hail Mary", author: "Andy Weir", status: .downloaded),
			LazyLibrarianBook(id: "2", title: "The City We Became", author: "N. K. Jemisin", status: .requested),
			LazyLibrarianBook(id: "3", title: "The House in the Cerulean Sea", author: "T. J. Klune", status: .wanted),
		]
		if query.isEmpty { return canned }
		return canned.filter {
			$0.title.localizedCaseInsensitiveContains(query)
				|| $0.author.localizedCaseInsensitiveContains(query)
		}
	}

	func requestBook(id: String, titleHint: String? = nil, authorHint: String? = nil) async throws -> LazyLibrarianRequest {
		if let existing = requests.first(where: { $0.id == id }) {
			return existing
		}
		let new = LazyLibrarianRequest(
			id: id,
			title: titleHint ?? "Requested \(id)",
			author: authorHint ?? "Unknown",
			status: .requested
		)
		requests.append(new)
		progress[id] = (ebook: 0, audio: 0)
		return new
	}

	func fetchRequests() async throws -> [LazyLibrarianRequest] {
		return requests
	}

	func searchBook(id: String, library: LazyLibrarianLibrary) async throws {
		// no-op for mock
	}

	func fetchDownloadProgress(limit: Int? = nil) async throws -> [LazyLibrarianDownloadProgressItem] {
		var items: [LazyLibrarianDownloadProgressItem] = []
		for (bookID, p) in progress {
			let ebook = min(100, p.ebook + 7)
			let audio = min(100, p.audio + 5)
			progress[bookID] = (ebook: ebook, audio: audio)

			items.append(
				LazyLibrarianDownloadProgressItem(
					bookID: bookID,
					auxInfo: "eBook",
					source: "SABNZBD",
					downloadID: "mock-\(bookID)-ebook",
					progress: ebook,
					finished: ebook >= 100
				)
			)
			items.append(
				LazyLibrarianDownloadProgressItem(
					bookID: bookID,
					auxInfo: "AudioBook",
					source: "SABNZBD",
					downloadID: "mock-\(bookID)-audio",
					progress: audio,
					finished: audio >= 100
				)
			)
		}
		return items
	}
}

