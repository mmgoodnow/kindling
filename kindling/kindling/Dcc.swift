import Foundation
import Network

class DCCFileTransfer {
    let filename: String
    let senderIP: String
    let port: UInt16
    let fileSize: UInt64
    var connection: NWConnection?
    var receivedData = Data()  // Data object to hold the file content in memory

    init(filename: String, senderIP: String, port: UInt16, fileSize: UInt64) {
        self.filename = filename
        self.senderIP = senderIP
        self.port = port
        self.fileSize = fileSize
    }

    // Function to start the DCC transfer and return the file content in memory asynchronously using async/await
    func startTransfer() async throws -> Data {
        let host = NWEndpoint.Host(senderIP)
        let port = NWEndpoint.Port(rawValue: port)!
        self.connection = NWConnection(host: host, port: port, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            self.connection?.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    print("Connected to \(self.senderIP):\(self.port)")
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

            self.connection?.start(queue: .global())
        }
    }

    // Private helper function to receive the file content in memory
    private func receiveFile(completion: @escaping (Result<Data, Error>) -> Void) {
        guard let connection = connection else { return }

        var receivedBytes: UInt64 = 0

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data {
                receivedBytes += UInt64(data.count)
                self.receivedData.append(data)
                print("Received \(receivedBytes)/\(self.fileSize) bytes")

                if receivedBytes >= self.fileSize {
                    print("File download complete!")
                    connection.cancel()
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
}
