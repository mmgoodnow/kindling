import Foundation

@main
struct CLI {
	static func main() async {
		do {
			try await run()
		} catch {
			fputs("error: \(error.localizedDescription)\n", stderr)
			exit(1)
		}
	}

	private static func run() async throws {
		let args = Array(CommandLine.arguments.dropFirst())
		guard args.count >= 2, args[0] == "ll" else {
			printUsage()
			return
		}

		let env = loadLazyEnv()
		guard
			let base = env.baseURL,
			let key = env.apiKey,
			let url = URL(string: base)
		else {
			throw LazyLibrarianError.notConfigured
		}
		let client = LazyLibrarianClient(baseURL: url, apiKey: key)

	switch args[1] {
	case "find":
		let query = args.dropFirst(2).joined(separator: " ")
		guard query.isEmpty == false else {
			print("find requires a query")
				return
			}
			let results = try await client.searchBooks(query: query)
			for book in results {
				print("\(book.id): \(book.title) — \(book.author) [\(book.status.rawValue)]")
			}
		case "request":
			guard args.count >= 3 else {
				print("request requires a book id")
				return
			}
			let id = args[2]
			let requested = try await client.requestBook(id: id)
			print("Requested \(requested.title) by \(requested.author) [\(requested.status.rawValue)]")
	default:
		printUsage()
	}
	}

	private static func printUsage() {
		print("""
Usage:
  ircli ll find <query>
  ircli ll request <bookid>
Env/.env: LL_BASE_URL, LL_API_KEY
""")
}

	private struct LazyEnv {
		let baseURL: String?
		let apiKey: String?
	}

	private static func loadLazyEnv() -> LazyEnv {
		let env = ProcessInfo.processInfo.environment
		var base = env["LL_BASE_URL"]
		var key = env["LL_API_KEY"]

		if let data = try? String(contentsOfFile: ".env") {
			data.split(separator: "\n").forEach { line in
				let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
				guard parts.count == 2 else { return }
				if parts[0] == "LL_BASE_URL" && base == nil { base = parts[1] }
				if parts[0] == "LL_API_KEY" && key == nil { key = parts[1] }
			}
		}

		return LazyEnv(baseURL: base, apiKey: key)
	}
}
