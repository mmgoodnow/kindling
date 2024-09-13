import Foundation
import Network

class IRCConnection {
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
    
    func start() {
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
      receiveMessages()
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
    
    func receiveMessages() {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
        if let data = data, !data.isEmpty {
          if let response = String(data: data, encoding: .utf8) {
            print("Received: \(response)")
            
            // Here you can handle responses from the server (e.g., CAP LS response, PING, etc.)
            if response.hasPrefix("PING") {
              self.handlePing(response)
            }
          }
        }
        
        if isComplete {
          print("Connection closed by server.")
        } else if let error = error {
          print("Error receiving message: \(error)")
        } else {
          // Continue receiving
          self.receiveMessages()
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
  }
