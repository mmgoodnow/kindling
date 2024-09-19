import Foundation

struct SearchResult {
	let original: String
	let bot: String
	let title: String
	let size: String?
	let hash: String?

	init?(from line: String) {
		let regex =
			/^!(?<bot>[\w-]+)( %(?<hash2>.+?)%)? (?<title>.+?)( ::INFO:: (?<size>.+?))?( ::HASH:: (?<hash>.+))?$/

		guard let match = line.wholeMatch(of: regex) else { return nil }

		self.original = line
		self.bot = String(match.output.bot)
		self.title = String(match.output.title)
		self.size = match.size.map { String($0) }
		self.hash = match.hash.map { String($0) } ?? match.hash2.map({ String($0) })
	}

	var ext: String {
		return URL(fileURLWithPath: title).pathExtension
	}
}
