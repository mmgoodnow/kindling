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

class EBookDownloader {
	let ircConnection: IRCConnection
	let ebooksChannel = "#ebooks"
	private var cancellables = Set<AnyCancellable>()

	init(ircConnection: IRCConnection) {
		self.ircConnection = ircConnection
	}

	public func start() async throws {
		try await ircConnection.start()
		try await ircConnection.join(channel: ebooksChannel)
	}

	func searchForEBook(query: String) async throws -> [SearchResult] {
		let searchMessage = "@Search \(query)"

		try await ircConnection.send(message: searchMessage, to: ebooksChannel)

		guard let dccSendMessage = await receiveDccSendMessage() else {
			throw EBookError.failedToReceiveDccSendMessage
		}

		guard let fileTransfer = DCCFileTransfer(dccSendMessage: dccSendMessage) else {
			throw EBookError.invalidDccSendMessage
		}

		guard let downloadedFileContents = try? await fileTransfer.download() else {
			throw EBookError.failedToDownloadFile
		}

		guard let extractedFiles = try? unzipData(downloadedFileContents) else {
			throw EBookError.failedToUnzipFile
		}

		guard let (_, fileData) = extractedFiles.first else {
			throw EBookError.noExtractedFilesFound
		}

		guard let fileContents = String(data: fileData, encoding: .utf8) else {
			throw EBookError.invalidFileContentsEncoding
		}

		return
			fileContents
			.components(separatedBy: .newlines)
			.filter { $0.hasPrefix("!") }
			.compactMap { SearchResult(from: $0) }
	}

	func download(searchResult: SearchResult) async throws -> (filename: String, data: Data) {
		// Send the search result original message to the ebooks channel
		try await ircConnection.send(message: searchResult.original, to: ebooksChannel)

		// Wait for a DCC SEND message
		guard let dccSendMessage = await receiveDccSendMessage() else {
			throw EBookError.failedToReceiveDccSendMessage
		}

		// Initialize a DCCFileTransfer based on the DCC SEND message
		guard let fileTransfer = DCCFileTransfer(dccSendMessage: dccSendMessage) else {
			throw EBookError.invalidDccSendMessage
		}

		guard let downloadedData = try? await fileTransfer.download() else {
			throw EBookError.failedToDownloadFile
		}
		return (fileTransfer.filename, downloadedData)
	}

	func receiveDccSendMessage() async -> String? {
		let dccSendMessagesStream =
			ircConnection
			.messages()
			.filter { $0.contains("DCC SEND") }
			.timeout(.seconds(10), scheduler: DispatchQueue.main)
		for await message in dccSendMessagesStream.values {
			return message
		}
		return nil
	}
}
