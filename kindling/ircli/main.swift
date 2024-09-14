import Foundation
import Network

func main() async {
	print("Running main")
	let ircConnection = IRCConnection(
		connection: NWConnection(
			host: "localhost", port: NWEndpoint.Port(6667), using: .tcp),
		nickname: "testnick",
		username: "testusername"
	)

	let downloader = EBookDownloader(ircConnection: ircConnection)

	do {
		if let fileData = try await downloader.searchForEBook(query: "swift programming") {
			print("Downloaded file size: \(fileData.count) bytes")
		} else {
			print("No file received.")
		}
	} catch {
		print("Failed to download eBook: \(error)")
	}
}

Task {
	await main()
}

RunLoop.main.run()
