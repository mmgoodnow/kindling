import Foundation
import Network

func main() async throws {
	let x = SearchResult(
		from: "!Oatmeal Maya Banks - (Eyes (Wild) 01) - Golden Eyes (Samhain) (retail).epub ::INFO:: 920.94KB")
	print(x?.metadata)
}

Task {
	try await main()
}

RunLoop.main.run()
