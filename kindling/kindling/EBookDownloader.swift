import Foundation
import Network

class EBookDownloader {
    let ircConnection: IRCConnection
    let ebooksChannel = "#ebooks"

    init(ircConnection: IRCConnection) {
        self.ircConnection = ircConnection
    }

    // Sends a search query in the form `@Search <query>` to the #ebooks channel
    func searchForEBook(query: String) async throws -> Data? {
        let searchMessage = "@Search \(query)"
		ircConnection.send(message: searchMessage, to: ebooksChannel)

        print("Search query sent: \(searchMessage)")
        
        // Listen for messages and handle DCC SEND requests
        return await receiveAndDownloadFile()
    }

    // Receives messages and downloads the file if a DCC SEND request is detected
    private func receiveAndDownloadFile() async -> Data? {
        while true {
            // Assume `ircConnection.receiveMessage()` is an async method that waits for an incoming message
            if let message = await ircConnection.receiveMessage() {
                // Handle the DCC SEND request if present
                if message.contains("\u{01}DCC SEND") {
                    // Extract file transfer info and initiate DCC file transfer
                    if let (filename, ip, port, fileSize) = ircConnection.parseDCCSendMessage(message) {
                        print("DCC SEND detected. Starting file download: \(filename), size: \(fileSize) bytes")

                        let humanReadableIP = ircConnection.convertDCCIP(ip)
                        let fileTransfer = DCCFileTransfer(filename: filename, senderIP: humanReadableIP, port: port, fileSize: fileSize)

                        do {
                            // Await file download
                            let fileData = try await fileTransfer.startTransfer()
                            print("File download complete. Size: \(fileData.count) bytes.")
                            return fileData  // Return the file data in memory
                        } catch {
                            print("File transfer failed: \(error)")
                            return nil
                        }
                    }
                }
            }
        }
    }
}
