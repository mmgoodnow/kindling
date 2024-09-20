import Foundation
import Network

func main() async throws {
	print("Running main")
	let ircConnection = IRCConnection(
		connection: NWConnection(
			host: "irc.irchighway.net", port: NWEndpoint.Port(6667), using: .tcp),
		nickname: "thankyoukindly",
		username: "thankyoukindly"
	)

	let downloader = EBookDownloader(ircConnection: ircConnection)
	try await downloader.start()

	let searchResults = try await downloader.searchForEBook(
		query: "the emperor of all maladies")

	let (filename, data) = try await downloader.download(searchResult: searchResults[1])
	print(data)
	print(filename)
}

Task {
	try await main()
}

RunLoop.main.run()
