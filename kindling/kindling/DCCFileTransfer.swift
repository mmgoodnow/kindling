import Foundation
import Network

class DCCFileTransfer {
	let filename: String
	let fileSize: UInt64
	var connection: NWConnection
	var receivedData = Data()

	init(connection: NWConnection, filename: String, fileSize: UInt64) {
		self.filename = filename
		self.fileSize = fileSize
		self.connection = connection
	}

	convenience init?(dccSendMessage: String) {
		// Example format: "nick!user@host DCC SEND <filename> <ip> <port> <filesize>"
		let components = dccSendMessage.split(separator: "DCC SEND")[1].trimmingCharacters(
			in: .whitespacesAndNewlines
		).trimmingCharacters(in: .init(charactersIn: "\u{1}")).split(
			separator: " ")

		// Ensure we have enough parts (DCC, SEND, filename, ip, port, filesize)
		guard components.count == 4,
			let ip = UInt32(components[1]),  // IP address as UInt32
			let port = UInt16(components[2]),  // Port as UInt16
			let fileSize = UInt64(components[3])  // File size as UInt64
		else {
			print("Invalid DCC SEND message format")
			return nil
		}

		let ipString = DCCFileTransfer.convertDCCIP(ip)

		let connection = NWConnection(
			host: NWEndpoint.Host(ipString), port: NWEndpoint.Port(rawValue: port)!,
			using: .tcp)

		self.init(
			connection: connection, filename: String(components[0]), fileSize: fileSize)
	}

	private static func convertDCCIP(_ ip: UInt32) -> String {
		let ipBytes = [
			UInt8((ip >> 24) & 0xFF),
			UInt8((ip >> 16) & 0xFF),
			UInt8((ip >> 8) & 0xFF),
			UInt8(ip & 0xFF),
		]
		return ipBytes.map { String($0) }.joined(separator: ".")
	}

	func download() async throws -> Data {
		return try await withCheckedThrowingContinuation { continuation in
			self.connection.stateUpdateHandler = { newState in
				switch newState {
				case .ready:
					self.receiveFile { result in
						continuation.resume(with: result)
					}
				case .failed(let error):
					print("Failed to connect: \(error)")
					continuation.resume(throwing: error)
				default:
					break
				}
			}

			self.connection.start(queue: .global())
		}
	}

	// Private helper function to receive the file content in memory
	private func receiveFile(
		completion: @escaping (Result<Data, Error>) -> Void
	) {
		var receivedBytes: UInt64 = 0

		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
			data, _, isComplete, error in
			if let data = data {
				receivedBytes += UInt64(data.count)
				self.receivedData.append(data)

				let acknowledgment = withUnsafeBytes(of: UInt32(receivedBytes).bigEndian) { Data($0) }
				self.connection.send(content: acknowledgment, completion: .contentProcessed({ _ in }))

				if receivedBytes >= self.fileSize {
					print("File download complete!")
					self.connection.cancel()
					completion(.success(self.receivedData))  // Return the in-memory file data
				} else {
					// Continue receiving more data until the file is fully downloaded
					self.receiveFile(completion: completion)
				}
			}

			if let error = error {
				print("Error receiving file: \(error)")
				completion(.failure(error))
			}
		}
	}
	
	deinit {
		connection.cancel()
	}
}
