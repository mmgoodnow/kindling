import Foundation

struct ProbableMetadata: Equatable, Hashable {
	let title: String
	let author: String
	let series: String?
}

struct SearchResult: Identifiable, Hashable {
	let id = UUID()
	let original: String
	let bot: String
	let filename: String
	let size: String?
	let hash: String?
	let metadata: ProbableMetadata?

	init?(from line: String) {
		let regex =
			/^!(?<bot>[\w-]+)( %?(?<hash2>[a-fA-F0-9]{12}) ?[%|])? (?<title>.+?)( ::INFO:: (?<size>.+?))?( ::HASH:: (?<hash>.+))?$/

		guard let match = line.wholeMatch(of: regex) else { return nil }

		self.original = line
		self.bot = String(match.output.bot)
		self.filename = String(match.output.title)
		self.size = match.size.map { String($0) }
		self.hash = (match.output.hash ?? match.output.hash2).map {
			String($0).lowercased()
		}
		self.metadata = SearchResult.getMetadata(filename: filename)
	}

	var ext: String {
		return URL(fileURLWithPath: filename).pathExtension
	}

	static func getMetadata(filename: String) -> ProbableMetadata? {

		// remove unnecessary information from end
		var bookName = filename

		if let match = bookName.firstMatch(
			of: /( [\[(][\w\d\.b]+[)\]])* ?\.[A-Za-z0-9]{2,4}$/)
		{
			bookName = String(bookName.prefix(upTo: match.range.lowerBound))
		}

		let components = bookName.split(separator: " - ")

		if components.count == 3 {
			let title = String(components[2])
			let seriesRegex = /[\[(](?<series>([^ ]+ ?)+\d{0,3})[\])]/

			if let match = components[1].wholeMatch(of: seriesRegex) {
				return ProbableMetadata(
					title: title,
					author: String(components[0]),
					series: String(match.output.series)
				)
			} else if let match = components[0].wholeMatch(of: seriesRegex) {
				return ProbableMetadata(
					title: title,
					author: String(components[1]),
					series: String(match.output.series)
				)

			}
		} else if components.count == 2 {
			return ProbableMetadata(
				title: String(components[1]),
				author: String(components[0]),
				series: nil
			)
		}
		return nil
	}
}
