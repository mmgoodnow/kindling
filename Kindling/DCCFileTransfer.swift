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
    let dccSendParameters = dccSendMessage.split(separator: "DCC SEND")[1].trimmingCharacters(
      in: .whitespacesAndNewlines
    ).trimmingCharacters(in: CharacterSet(charactersIn: "\u{1}"))

    let regex = /^"?(?<filename>.+?)"? (?<ip>\d+) (?<port>\d+) (?<fileSize>\d+)$/

    guard let match = dccSendParameters.wholeMatch(of: regex) else {
      print("Invalid DCC SEND message format")
      return nil
    }

    let filename = String(match.output.filename)
    guard let ip = UInt32(match.output.ip),
      let port = UInt16(match.output.port),
      let fileSize = UInt64(match.output.fileSize)
    else {
      print("Invalid IP, port, or file size format")
      return nil
    }

    let ipString = DCCFileTransfer.convertDCCIP(ip)

    let connection = NWConnection(
      host: NWEndpoint.Host(ipString), port: NWEndpoint.Port(rawValue: port)!,
      using: .tcp
    )

    self.init(connection: connection, filename: filename, fileSize: fileSize)
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

  // Method to download the file by accumulating received chunks
  func download() async throws -> Data {
    var totalBytesReceived: UInt64 = 0

    connection.start(queue: .global())

    while totalBytesReceived < fileSize {
      let (data, isComplete) = try await receiveChunk()
      receivedData.append(data)
      totalBytesReceived += UInt64(data.count)
      let acknowledgment = withUnsafeBytes(of: UInt32(totalBytesReceived).bigEndian) { Data($0) }
      self.connection.send(content: acknowledgment, completion: .contentProcessed({ _ in }))
      if isComplete {
        print("Connection completed before receiving the full file.")
        break
      }
    }

    return receivedData
  }

  // Method to receive data chunks
  private func receiveChunk() async throws -> (Data, Bool) {
    return try await withCheckedThrowingContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
        data, _, isComplete, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }

        guard let data = data else {
          continuation.resume(throwing: NSError(domain: "No data received", code: -1))
          return
        }

        continuation.resume(returning: (data, isComplete))
      }
    }
  }

  deinit {
    connection.cancel()
  }
}
