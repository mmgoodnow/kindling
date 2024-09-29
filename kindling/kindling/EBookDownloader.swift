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
	let ebooksChannel: String
	private var cancellables = Set<AnyCancellable>()

	init(ircConnection: IRCConnection, ebooksChannel: String) {
		self.ircConnection = ircConnection
		self.ebooksChannel = ebooksChannel
	}

	public func start() async throws {
		print("Starting")
		try await ircConnection.start()
		print("Joining")
		try await ircConnection.join(channel: ebooksChannel)
	}

	func searchForEBook(
		query: String, onProgress: (_ status: String, _ current: Int, _ total: Int) -> Void
	)
		async throws -> [SearchResult]
	{
		let total = 7

		let searchMessage = "@Search \(query)"
		onProgress("Sending search query", 1, total)

		try await ircConnection.send(message: searchMessage, to: ebooksChannel)

		onProgress("Waiting to receive search results", 2, total)
		guard let dccSendMessage = await receiveDccSendMessage() else {
			throw EBookError.failedToReceiveDccSendMessage
		}
		print(dccSendMessage)

		onProgress("Parsing DCC SEND message", 3, total)
		guard let fileTransfer = DCCFileTransfer(dccSendMessage: dccSendMessage) else {
			throw EBookError.invalidDccSendMessage
		}
		print(fileTransfer.filename)

		onProgress("Downloading search results", 4, total)
		guard let downloadedFileContents = try? await fileTransfer.download() else {
			throw EBookError.failedToDownloadFile
		}

		print("downloaded file contents")
		onProgress("Unzipping search results", 5, total)
		guard let extractedFiles = try? unzipData(downloadedFileContents) else {
			throw EBookError.failedToUnzipFile
		}
		print("extracted files")
		
		onProgress("Extracting search results", 6, total)
		guard let (_, fileData) = extractedFiles.first else {
			throw EBookError.noExtractedFilesFound
		}
		guard let fileContents = String(data: fileData, encoding: .utf8) else {
			throw EBookError.invalidFileContentsEncoding
		}
		print("unzipped")
		let results =
			fileContents
			.components(separatedBy: .newlines)
			.filter { $0.hasPrefix("!") }
			.compactMap { SearchResult(from: $0) }
		onProgress("Done", total, total)
		return results

	}

	func download(searchResult: SearchResult) async throws -> (filename: String, data: Data) {
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

	func receiveDccSendMessage() async -> String? {
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
}
