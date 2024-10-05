import Combine
import Foundation
import Network

enum IRCError: Error {
	case timeout
	case dataNotDecodable
}

class IRCConnection {
	let connection: NWConnection
	let nickname: String
	let username: String
	var stateReporter: StateReporter
	private var cancellables = Set<AnyCancellable>()
	private let messageSubject = PassthroughSubject<String, Never>()
	
	init(
		connection: NWConnection, nickname: String, username: String, stateReporter: StateReporter
	) {
		self.connection = connection
		self.nickname = nickname
		self.username = username
		self.stateReporter = stateReporter
	}

	public func start() async throws {
		// Wait for the connection to become ready
		publishReceivedMessages()
		logReceivedMessages()
		await withCheckedContinuation { continuation in
			self.connection.stateUpdateHandler = { newState in
				self.stateReporter.nwConnectionState = newState
				switch newState {
				case .ready:
					print("Connection ready")
					continuation.resume()
				case .failed(let error):
					print("Connection failed with error: \(error)")
				default:
					print("connection state changed to \(newState)")
					break
				}
			}
			connection.start(queue: .global())
		}
		handlePings()
		handleCTCPVersionRequests()
		try await register()
	}

	private func publishReceivedMessages() {
		Task {
			var buffer = Data()

			while true {
				if let chunk = try await self.receiveMessage() {
					buffer.append(chunk)
					let delimiter = Data("\r\n".utf8)
					var messages = buffer.split(separator: delimiter)

					if buffer.suffix(delimiter.count) == delimiter {
						buffer = Data()
					} else {
						buffer = messages.popLast() ?? Data()
					}

					for messageData in messages where !messageData.isEmpty {
						if let message = String(
							data: messageData, encoding: .utf8)
						{
							messageSubject.send(message)
						} else if let message = String(
							data: messageData, encoding: .isoLatin1)
						{
							messageSubject.send(message)
						} else {
							print(
								"Error decoding message: \(messageData)"
							)
						}
					}
				} else {
					break
				}
			}
		}
	}

	// will suspend waiting for new messages to come in
	func receiveMessage() async throws -> Data? {
		return try await withCheckedThrowingContinuation { continuation in
			connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
				data, _, isComplete, error in
				if let data = data {
					continuation.resume(returning: data)
				} else if let error = error {
					print("Receive error: \(error)")
					continuation.resume(throwing: error)
				} else if isComplete {
					print("Connection is complete")
					continuation.resume(returning: nil)
				}
			}
		}
	}

	private func send(raw message: String) async throws {
		let messageWithNewline = message + "\r\n"
		let data = messageWithNewline.data(using: .utf8)!
		print("send: \(message)")
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, Error>) in
			connection.send(
				content: data,
				completion: .contentProcessed { error in
					if let error = error {
						continuation.resume(throwing: error)
					} else {
						continuation.resume(returning: ())
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

	func register() async throws {
		let isRegistered = CurrentValueSubject<Bool, Never>(false)
		let cancellable = messages()
			.filter { message in
				let components = message.split(
					separator: " ", omittingEmptySubsequences: true)
				return components.count >= 2 && components[1] == "001"
			}
			.sink { _ in
				isRegistered.send(true)
			}

		try await self.send(raw: "NICK \(self.nickname)")
		try await self.send(raw: "USER \(self.username) 0 * :\(self.username)")

		let timeoutPublisher =
			isRegistered
			.first { $0 }
			.timeout(.seconds(10), scheduler: DispatchQueue.main)

		let isSuccessful = await timeoutPublisher.values.first { $0 } ?? false

		cancellable.cancel()
		guard isSuccessful else {
			throw IRCError.timeout
		}
	}

	func handlePings() {
		messages()
			.filter { message in
				let components = message.split(
					separator: " ", omittingEmptySubsequences: true)
				return components.count == 2 && components[0] == "PING"
			}
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
		messages()
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
		let versionResponse = "Swindling 2.0"
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

	func logReceivedMessages() {
		messages()
			.sink { print("recv: \($0)") }
			.store(in: &cancellables)
	}

	public func messages() -> AnyPublisher<String, Never> {
		return messageSubject.eraseToAnyPublisher()
	}
	
	func cleanup() async throws {
		try await send(raw: "QUIT")
		connection.cancel()
	}

	deinit {
		connection.cancel()
	}
}
