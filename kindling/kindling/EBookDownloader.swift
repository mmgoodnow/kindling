import Combine
import Foundation
import Network
import ZIPFoundation

func unzipData(_ zipData: Data) throws -> [String: Data] {
	var extractedFiles = [String: Data]()

	let archive = try Archive(data: zipData, accessMode: .read)

	// Iterate over the entries in the ZIP file
	for entry in archive {
		if entry.type == .file {
			var entryData = Data()
			let _ = try archive.extract(entry) { data in
				entryData.append(data)
			}
			// Store the extracted data in the dictionary
			extractedFiles[entry.path] = entryData
		}
	}

	return extractedFiles
}

enum EBookError: Error {
	case failedToReceiveDccSendMessage
	case invalidDccSendMessage
	case failedToDownloadFile
	case failedToUnzipFile
	case noExtractedFilesFound
	case invalidFileContentsEncoding
}

actor EBookDownloader {
	let ircConnection: IRCConnection
	let ebooksChannel: String
	let reporter: ProgressReporter
	private var cancellables = Set<AnyCancellable>()

	init(ircConnection: IRCConnection, ebooksChannel: String, reporter: ProgressReporter) {
		self.ircConnection = ircConnection
		self.ebooksChannel = ebooksChannel
		self.reporter = reporter
	}

	public func start() async throws {
		print("Starting")
		try await ircConnection.start()
		print("Joining")
		try await ircConnection.join(channel: ebooksChannel)
	}

	public func search(query: String)
		async throws -> [SearchResult]
	{
		reporter.total = 8
		let searchBot = "SearchOok"
		let searchMessage = "@\(searchBot) \(query)"
		reporter.tick("Sending search query")
		// subscribe to messages received earlier than sending
		let cancellable = ircConnection.messages().filter { msg in

			let a = msg.contains("PRIVMSG") || msg.contains("NOTICE")
			let b = msg.contains(searchBot)
			let c = msg.contains("accepted")
			print(a, b, c, msg)
			return a && b && c
		}.sink { _ in
			self.reporter.tick("Waiting to receive search results")
		}
		try await ircConnection.send(message: searchMessage, to: ebooksChannel)

		reporter.tick("Waiting for search to be accepted")

		guard let dccSendMessage = await receiveDccSendMessage() else {
			throw EBookError.failedToReceiveDccSendMessage
		}

		cancellable.cancel()

		reporter.tick("Parsing DCC SEND message")
		guard let fileTransfer = DCCFileTransfer(dccSendMessage: dccSendMessage) else {
			throw EBookError.invalidDccSendMessage
		}

		reporter.tick("Downloading search results")
		guard let downloadedFileContents = try? await fileTransfer.download() else {
			throw EBookError.failedToDownloadFile
		}

		reporter.tick("Unzipping search results")
		guard let extractedFiles = try? unzipData(downloadedFileContents) else {
			throw EBookError.failedToUnzipFile
		}

		reporter.tick("Extracting search results")
		guard let (_, fileData) = extractedFiles.first else {
			throw EBookError.noExtractedFilesFound
		}
		guard let fileContents = String(data: fileData, encoding: .utf8) else {
			throw EBookError.invalidFileContentsEncoding
		}
		let results =
			fileContents
			.components(separatedBy: .newlines)
			.filter { $0.hasPrefix("!") }
			.compactMap { SearchResult(from: $0) }
		reporter.complete("Done")
		return results

	}

	public func download(searchResult: SearchResult) async throws -> (
		filename: String, data: Data
	) {
		// Send the search result original message to the ebooks channel
		try await ircConnection.send(message: searchResult.original, to: ebooksChannel)

		// Wait for a DCC SEND message
		guard let dccSendMessage = await receiveDccSendMessage() else {
			throw EBookError.failedToReceiveDccSendMessage
		}

		print("received dcc send message")

		// Initialize a DCCFileTransfer based on the DCC SEND message
		guard let fileTransfer = DCCFileTransfer(dccSendMessage: dccSendMessage) else {
			throw EBookError.invalidDccSendMessage
		}

		print("created file transfer")

		guard let downloadedData = try? await fileTransfer.download() else {
			throw EBookError.failedToDownloadFile
		}

		print("downloaded \(fileTransfer.filename)")

		return (fileTransfer.filename, downloadedData)
	}

	private func receiveDccSendMessage() async -> String? {
		let dccSendMessagesStream =
			ircConnection
			.messages()
			.filter { return $0.contains("DCC SEND") }
			.timeout(.seconds(30), scheduler: DispatchQueue.main)
		for await message in dccSendMessagesStream.values {
			return message
		}
		return nil
	}

	public func cleanup() async throws {
		try await ircConnection.cleanup()
	}
}
