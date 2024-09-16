import Combine
import Foundation
import Network

class IRCConnection {
	let connection: NWConnection
	let nickname: String
	let username: String

	// To manage Combine subscriptions
	private var cancellables = Set<AnyCancellable>()
	private let messageSubject = PassthroughSubject<String, Never>()

	init(
		connection: NWConnection, nickname: String, username: String
	) {
		self.connection = connection
		self.nickname = nickname
		self.username = username
	}

	public func start() async throws {
		// Wait for the connection to become ready
		self.publishReceivedMessages()
		await withCheckedContinuation { continuation in
			self.connection.stateUpdateHandler = { newState in
				switch newState {
				case .ready:
					print("Connection ready")
					continuation.resume()
				case .failed(let error):
					print("Connection failed with error: \(error)")
					continuation.resume()  // Resume continuation even in case of failure
				default:
					break
				}
			}
			connection.start(queue: .global())
		}
		logReceivedMessages()
		handlePings()
		handleCTCPVersionRequests()
		try await capNegotiate()
	}

	private func publishReceivedMessages() {
		Task {
			while true {
				if let message = await receiveMessage() {
					messageSubject.send(message)
				}
			}
		}
	}

	// will suspend waiting for new messages to come in
	func receiveMessage() async -> String? {
		return await withCheckedContinuation { continuation in
			connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
				data, _, isComplete, error in
				if let data = data, !data.isEmpty {
					if let message = String(data: data, encoding: .utf8) {
						continuation.resume(
							returning: message.trimmingCharacters(
								in: .newlines))
					} else {
						continuation.resume(returning: nil)
					}
				} else if error != nil {
					continuation.resume(returning: nil)
				} else if isComplete {
					continuation.resume(returning: nil)
				}
			}
		}
	}

	func capNegotiate() async throws {
		// Start CAP negotiation by asking the server what capabilities it supports
		try await send(raw: "CAP LS 302")
		// Authenticate (send NICK and USER command to IRC server)
		try await send(raw: "NICK \(nickname)")
		try await send(raw: "USER \(username) 0 * :\(username)")
		try await send(raw: "CAP END")
	}

	private func send(raw message: String) async throws {
		let messageWithNewline = message + "\r\n"
		let data = messageWithNewline.data(using: .utf8)!
		print("send: \(message)")
		// Wrap send in async/await
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, Error>) in
			connection.send(
				content: data,
				completion: .contentProcessed { error in
					if let error = error {
						continuation.resume(throwing: error)  // Resume with error
					} else {
						continuation.resume(returning: ())  // Resume with success
					}
				})
		}
	}

	public func send(message: String, to channel: String) async throws {
		let formattedMessage = "PRIVMSG \(channel) :\(message)"
		try await send(raw: formattedMessage)
	}

	public func join(channel: String) async throws {
		let joinMessage = "JOIN \(channel)"
		try await send(raw: joinMessage)
	}

	func handlePings() {
		messageSubject
			.filter { $0.contains("PING") }
			.sink { message in
				Task {
					let pongMessage = message.replacingOccurrences(
						of: "PING", with: "PONG")
					do {
						try await self.send(raw: pongMessage)
					} catch {
						print("error sending ping: \(error)")
					}
				}
			}
			.store(in: &cancellables)
	}

	func handleCTCPVersionRequests() {
		messageSubject
			.filter { $0.contains("\u{01}VERSION\u{01}") }
			.sink { message in
				Task {
					// :nick!user@host PRIVMSG <your_nickname> :\x01VERSION\x01
					if let sender = self.extractSender(from: message) {
						do {
							try await self.respondToCTCPVersionRequest(
								from: sender)
						} catch {
							print(
								"error responding to CTCP Version request: \(error)"
							)
						}
					}
				}
			}
			.store(in: &cancellables)
	}

	// Respond to a CTCP VERSION request
	func respondToCTCPVersionRequest(from sender: String) async throws {
		let versionResponse = "MySwiftIRCClient 1.0"
		let ctcpVersionResponse = "\u{01}VERSION \(versionResponse)\u{01}"
		try await send(raw: "NOTICE \(sender) :\(ctcpVersionResponse)")
	}

	// Helper function to extract the sender's nickname from the message
	func extractSender(from message: String) -> String? {
		// Example format: ":nick!user@host PRIVMSG your_nickname :\x01VERSION\x01"
		let components = message.split(separator: " ")
		if let senderComponent = components.first, senderComponent.hasPrefix(":") {
			// Remove the leading colon and extract the nickname part (before the `!`)
			let sender = senderComponent.dropFirst().split(separator: "!").first
			return sender.map { String($0) }
		}
		return nil
	}

	// Function to handle DCC SEND requests using async/await
	func handleDCCSend(_ message: String) async {
		// PRIVMSG you :\u{01}DCC SEND <filename> <ip> <port> <filesize>\u{01}
		if message.contains("\u{01}DCC SEND") {
			if let (filename, ip, port, fileSize) = parseDCCSendMessage(message) {
				print(
					"DCC SEND request received for file: \(filename), size: \(fileSize) bytes"
				)

				let humanReadableIP = convertDCCIP(ip)

				let fileTransfer = DCCFileTransfer(
					filename: filename, senderIP: humanReadableIP, port: port,
					fileSize: fileSize)

				do {
					let fileData = try await fileTransfer.startTransfer()
					print(
						"File successfully downloaded in memory. Size: \(fileData.count) bytes."
					)
				} catch {
					print("File transfer failed: \(error)")
				}
			}
		}
	}

	// Function to parse DCC SEND message and extract filename, IP, port, and file size
	func parseDCCSendMessage(_ message: String) -> (String, UInt32, UInt16, UInt64)? {
		// Extract DCC SEND parts: "DCC SEND <filename> <ip> <port> <filesize>"
		let parts = message.split(separator: " ")
		guard parts.count >= 6 else { return nil }

		let filename = String(parts[3])
		if let ip = UInt32(parts[4]), let port = UInt16(parts[5]),
			let fileSize = UInt64(parts[6])
		{
			return (filename, ip, port, fileSize)
		}
		return nil
	}

	// Convert DCC IP from integer to human-readable IP format
	func convertDCCIP(_ ip: UInt32) -> String {
		let ipBytes = [
			UInt8((ip >> 24) & 0xFF),
			UInt8((ip >> 16) & 0xFF),
			UInt8((ip >> 8) & 0xFF),
			UInt8(ip & 0xFF),
		]
		return ipBytes.map { String($0) }.joined(separator: ".")
	}

	func logReceivedMessages() {
		messageSubject
			.sink { print("recv: \($0)") }
			.store(in: &cancellables)
	}
}
