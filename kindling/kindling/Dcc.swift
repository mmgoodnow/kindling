import Foundation
import Network

class DCCFileTransfer {
    let filename: String
    let senderIP: String
    let port: UInt16
    let fileSize: UInt64
    var connection: NWConnection?
    var receivedData = Data()
    
    init(filename: String, senderIP: String, port: UInt16, fileSize: UInt64) {
        self.filename = filename
        self.senderIP = senderIP
        self.port = port
        self.fileSize = fileSize
    }
    
    // Start the DCC file transfer and return a completion handler with the downloaded file data
    func startTransfer(completion: @escaping (Result<Data, Error>) -> Void) {
        let host = NWEndpoint.Host(senderIP)
        let port = NWEndpoint.Port(rawValue: port)!
        self.connection = NWConnection(host: host, port: port, using: .tcp)
        
        connection?.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("Connected to \(self.senderIP):\(self.port)")
                self.receiveFile(completion: completion)
            case .failed(let error):
                print("Failed to connect: \(error)")
                completion(.failure(error))
            default:
                break
            }
        }
        
        connection?.start(queue: .global())
    }
    
    private func receiveFile(completion: @escaping (Result<Data, Error>) -> Void) {
        guard let connection = connection else { return }
        
        var receivedBytes: UInt64 = 0
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let error = error {
                print("Error receiving file: \(error)")
                completion(.failure(error))
                return
            }
            
            if let data = data {
                receivedBytes += UInt64(data.count)
                self.receivedData.append(data)
                print("Received \(receivedBytes)/\(self.fileSize) bytes")
                
                if receivedBytes >= self.fileSize {
                    print("File download complete!")
                    connection.cancel()
                    completion(.success(self.receivedData))
                } else {
                    // Continue receiving more data until the file is fully downloaded
                    self.receiveFile(completion: completion)
                }
            }
        }
    }
}
