import Foundation
import Network

class IRCConnection {
  let connection: NWConnection
  let nickname: String
  let username: String
  let server: String
  let capabilities: [String]
  
  init(connection: NWConnection, nickname: String, username: String, server: String, capabilities: [String]) {
    self.connection = connection
    self.nickname = nickname
    self.username = username
    self.server = server
    self.capabilities = capabilities
  }
  
  func start() async {
    connection.stateUpdateHandler = { newState in
      switch newState {
      case .ready:
        print("Connection established")
        self.capNegotiate()
      case .failed(let error):
        print("Connection failed: \(error)")
      default:
        break
      }
    }
    
    connection.start(queue: .global())
    
    // Receive data continuously
    await receiveMessages()
  }
  
  func capNegotiate() {
    // Start CAP negotiation by asking the server what capabilities it supports
    send("CAP LS")
    
    // After receiving the response, request specific capabilities (example: multi-prefix and userhost-in-names)
    let requestedCaps = capabilities.joined(separator: " ")
    send("CAP REQ :\(requestedCaps)")
    
    // End CAP negotiation
    send("CAP END")
    
    // Authenticate (send NICK and USER command to IRC server)
    send("NICK \(nickname)")
    send("USER \(username) 0 * :\(username)")
  }
  
  func send(_ message: String) {
    let messageWithNewline = message + "\r\n"
    let data = messageWithNewline.data(using: .utf8)!
    
    connection.send(content: data, completion: .contentProcessed({ error in
      if let error = error {
        print("Failed to send message: \(error)")
      }
    }))
  }
  
  func receiveMessages() async {
    while true {
      do {
        let data = try await receiveData()
        
        if let response = String(data: data, encoding: .utf8) {
          print("Received: \(response)")
          
          // Handle server responses (e.g., PING, CAP LS)
          if response.hasPrefix("PING") {
            handlePing(response)
          }
          
          // Additional handling for other IRC commands can go here
        }
      } catch {
        print("Error receiving message: \(error)")
        break // Exit the loop if an error occurs
      }
    }
  }
  
  // Helper function to asynchronously receive data from the connection
  private func receiveData() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
        if let data = data, !data.isEmpty {
          continuation.resume(returning: data)
        } else if let error = error {
          continuation.resume(throwing: error)
        } else if isComplete {
          continuation.resume(throwing: NSError(domain: "ConnectionClosed", code: 1, userInfo: nil))
        }
      }
    }
  }
  
  func handlePing(_ pingMessage: String) {
    // Reply to server PING with PONG to keep the connection alive
    let pongMessage = pingMessage.replacingOccurrences(of: "PING", with: "PONG")
    send(pongMessage)
  }
  
  // Function to handle CTCP requests like VERSION
  func handleCTCP(_ message: String) {
    // CTCP messages are usually in the format: PRIVMSG <your_nickname> :\x01VERSION\x01
    if message.contains("\u{01}VERSION\u{01}") {
      // Extract the sender's nickname (example message: ":nick!user@host PRIVMSG your_nickname :\x01VERSION\x01")
      if let sender = extractSender(from: message) {
        respondToCTCPVersionRequest(from: sender)
      }
    }
  }
  
  // Respond to a CTCP VERSION request
  func respondToCTCPVersionRequest(from sender: String) {
    let versionResponse = "MySwiftIRCClient 1.0"
    let ctcpVersionResponse = "\u{01}VERSION \(versionResponse)\u{01}"
    send("NOTICE \(sender) :\(ctcpVersionResponse)")
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
    // Example DCC SEND message: PRIVMSG your_nickname :\u{01}DCC SEND <filename> <ip> <port> <filesize>\u{01}
    if message.contains("\u{01}DCC SEND") {
      // Parse the DCC SEND message
      if let (filename, ip, port, fileSize) = parseDCCSendMessage(message) {
        print("DCC SEND request received for file: \(filename), size: \(fileSize) bytes")
        
        // Convert IP from integer to human-readable format
        let humanReadableIP = convertDCCIP(ip)
        
        // Initialize DCCFileTransfer and start the download
        let fileTransfer = DCCFileTransfer(filename: filename, senderIP: humanReadableIP, port: port, fileSize: fileSize)
        
        do {
          // Await the file transfer result
          let fileData = try await fileTransfer.startTransfer()
          print("File successfully downloaded in memory. Size: \(fileData.count) bytes.")
          // Do something with the downloaded file data in memory
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
    if let ip = UInt32(parts[4]), let port = UInt16(parts[5]), let fileSize = UInt64(parts[6]) {
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
      UInt8(ip & 0xFF)
    ]
    return ipBytes.map { String($0) }.joined(separator: ".")
  }
}
