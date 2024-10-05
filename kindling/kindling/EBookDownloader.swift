import Combine
import Foundation
import Network
import ZIPFoundation

struct BookFile {
	let filename: String
	let searchResult: SearchResult
	let data: Data
}

enum EBookError: Error {
	case failedToReceiveDccSendMessage
	case invalidDccSendMessage
	case failedToDownloadFile
	case failedToUnzipFile
	case noExtractedFilesFound
	case invalidFileContentsEncoding
	
	var localizedDescription: String {
		switch self {
		case .failedToReceiveDccSendMessage:
			return "Failed to receive the DCC SEND message."
		case .invalidDccSendMessage:
			return "The DCC SEND message was invalid."
		case .failedToDownloadFile:
			return "Failed to download the file."
		case .failedToUnzipFile:
			return "Failed to unzip the file."
		case .noExtractedFilesFound:
			return "No extracted files were found."
		case .invalidFileContentsEncoding:
			return "The file contents could not be decoded."
		}
	}
}

actor EBookDownloader {
	let ircConnection: IRCConnection
	let ebooksChannel: String
	let stateReporter: StateReporter
	private var cancellables = Set<AnyCancellable>()

	init(
		ircConnection: IRCConnection,
		ebooksChannel: String,
		stateReporter: StateReporter
	) {
		self.ircConnection = ircConnection
		self.ebooksChannel = ebooksChannel
		self.stateReporter = stateReporter
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

	private func unzipData(_ zipData: Data) throws -> [String: Data] {
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

	public func start() async throws {
		stateReporter.registrationState = .loading
		do {
			try await ircConnection.start()
			try await ircConnection.join(channel: ebooksChannel)
		} catch {
			stateReporter.registrationState = .failed
			throw error
		}
		stateReporter.registrationState = .ready
	}

	public func search(query: String, progressReporter: ProgressReporter)
		async throws -> [SearchResult]
	{
		do {
			progressReporter.start(9)
			let searchBot = "Search"
			let searchMessage = "@\(searchBot) \(query)"
			progressReporter.tick("Sending search query")
			// subscribe to messages received earlier than sending
			let cancellable = ircConnection.messages().filter { msg in

				let a = msg.contains("PRIVMSG") || msg.contains("NOTICE")
				let b = msg.contains(searchBot)
				let c = msg.contains("accepted")
				return a && b && c
			}.sink { _ in
				progressReporter.tick("Waiting to receive search results")
			}
			try await ircConnection.send(message: searchMessage, to: ebooksChannel)

			progressReporter.tick("Waiting for search to be accepted")

			guard let dccSendMessage = await receiveDccSendMessage() else {
				throw EBookError.failedToReceiveDccSendMessage
			}

			cancellable.cancel()

			progressReporter.tick("Parsing DCC SEND message")
			guard let fileTransfer = DCCFileTransfer(dccSendMessage: dccSendMessage)
			else {
				throw EBookError.invalidDccSendMessage
			}

			progressReporter.tick("Downloading search results")
			guard let downloadedFileContents = try? await fileTransfer.download() else {
				throw EBookError.failedToDownloadFile
			}

			progressReporter.tick("Unzipping search results")
			guard let extractedFiles = try? unzipData(downloadedFileContents) else {
				throw EBookError.failedToUnzipFile
			}

			progressReporter.tick("Extracting search results")
			guard let (_, fileData) = extractedFiles.first else {
				throw EBookError.noExtractedFilesFound
			}
			guard let fileContents = String(data: fileData, encoding: .utf8) else {
				throw EBookError.invalidFileContentsEncoding
			}
			progressReporter.tick("Parsing search results")
			let results =
				fileContents
				.components(separatedBy: .newlines)
				.filter { $0.hasPrefix("!") }
				.compactMap { SearchResult(from: $0) }
			progressReporter.complete("Done")
			return results
		} catch {
			progressReporter.reset()
			throw error
		}

	}

	public func download(searchResult: SearchResult, progressReporter: ProgressReporter) async throws -> (
		filename: String, data: Data
	) {
		progressReporter.start(5)
		progressReporter.tick("Sending download request")
		try await ircConnection.send(message: searchResult.original, to: ebooksChannel)

		progressReporter.tick("Waiting for \(searchResult.bot) to respond")
		guard let dccSendMessage = await receiveDccSendMessage() else {
			throw EBookError.failedToReceiveDccSendMessage
		}

		progressReporter.tick("Parsing DCC SEND message")
		guard let fileTransfer = DCCFileTransfer(dccSendMessage: dccSendMessage) else {
			throw EBookError.invalidDccSendMessage
		}

		progressReporter.tick("Downloading")
		guard let downloadedData = try? await fileTransfer.download() else {
			throw EBookError.failedToDownloadFile
		}
		progressReporter.complete("Done")

		return (fileTransfer.filename, downloadedData)
	}

	public func cleanup() async throws {
		try await ircConnection.cleanup()
	}
}
