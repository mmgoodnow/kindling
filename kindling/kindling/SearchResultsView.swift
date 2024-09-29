import SwiftUI

extension SearchResult {
	// returns int for sorting
	var isPreferredBot: Int {
		return bot == "Oatmeal" ? 1 : 0
	}
}

struct SearchResultsView: View {
	let searchResults: [SearchResult]
	let onDownload: (SearchResult) -> Void

	var smartSearchResults: [SearchResult] {
		let comparators: [SortDescriptor<SearchResult>] = [
			SortDescriptor(\.metadata?.author),
			SortDescriptor(\.metadata?.series),
			SortDescriptor(\.isPreferredBot, order: .reverse),
			SortDescriptor(\.bot),
		]
		return searchResults.filter { result in
			result.ext == "epub"
		}
		.sorted(using: comparators)
	}

	var body: some View {
		List(smartSearchResults) { result in
			HStack {
				VStack(alignment: .leading) {
					if let metadata = result.metadata {
						Text(metadata.title)
							.font(.headline)
						if let series = metadata.series {
							Text(metadata.author)
								.font(.subheadline)
							Text(series).font(.subheadline)
						} else {
							Text(metadata.author).font(.subheadline)
						}
					} else {
						Text(result.filename)
							.font(.headline)
					}
					Text("\(result.bot)\(result.size.map {" " + $0} ?? "")")
						.font(.subheadline)
						.foregroundColor(.gray)
				}
				Spacer(minLength: 18)
				Button(action: { onDownload(result) }) {
					Image(systemName: "arrow.down.circle")
						.font(.title2)
						.foregroundColor(.blue)
				}
			}

		}.overlay {
			if searchResults.isEmpty {
				ContentUnavailableView.search
			}
		}
	}
}

#Preview {
	let rawResults = """
		Search results from SearchBot v3.00.07 by Ook, searching dll written by Ook, Based on Searchbot v2.22 by Dukelupus
		Searched 14 lists for "Wild Eyes" , found 96 matches. Enjoy!
		This list includes results from ALL the lists SearchBot v3.00.07 currently has, some of these servers may be offline.
		Always check to be sure the server you want to make a request from is actually in the channel, otherwise your request will have no effect.
		For easier searching, use sbClient script (also very fast local searches). You can get that script by typing @sbClient in the channel.

		!Pondering-EBooks Daisy Dexter Dobbs - [Wild Winter 13] - Forever Blue Eyes (EC) (pdf).rar  ::INFO:: 363KB ::HASH:: 52dad3c997eff72d
		!Pondering-EBooks Wild Winter - [13] - Forever Blue Eyes - Daisy Dexter Dobbs (EC) (pdf).rar  ::INFO:: 363KB ::HASH:: 2e448057a105ea10
		!Pondering-EBooks [Wild Winter 13] - Daisy Dexter Dobbs - Forever Blue Eyes (EC) (htm).rar  ::INFO:: 625KB ::HASH:: 98b49ff594928d74
		!Pondering-EBooks Daisy Dexter Dobbs - [Wild Winter 13] - Forever Blue Eyes (html).rar  ::INFO:: 188KB ::HASH:: 8852febb695ee268
		!Pondering-EBooks Daisy Dexter Dobbs - [Wild Winter 13] - Forever Blue Eyes (lit).rar  ::INFO:: 133KB ::HASH:: c28c484fdf2b6a0c
		!Pondering-EBooks Wendelin Van Draanen - [Sammy Keyes 11] - Sammy Keyes and the Wild Things (retail) (epub).rar  ::INFO:: 673KB ::HASH:: 668ce9a3a0c0d9c0
		!Pondering-EBooks Camiel Rollins - [Wild Night Dreaming 01] - Mr Blue Eyes (epub).rar  ::INFO:: 137KB ::HASH:: c9d90bcf145fd494
		!Pondering-EBooks Maya Banks - [Eyes (Wild) 01] - Golden Eyes [Samhain] (retail) (epub).rar  ::INFO:: 1MB ::HASH:: def1cf37740fadc
		!Pondering-EBooks Maya Banks - [Eyes (Wild) 02] - Amber Eyes [Samhain] (retail) (epub).rar  ::INFO:: 621KB ::HASH:: 8dba818300a278f5
		!Pondering-EBooks Kathy Lyons - [Grizzlies Gone Wild 03] - For the Bear's Eyes Only (epub).rar  ::INFO:: 876KB ::HASH:: 354e7f44ca16fee9
		!Pondering-EBooks Danielle Stewart - [The Barrington Billionaires 02] - Wild Eyes (epub).rar  ::INFO:: 344KB ::HASH:: 6b99648b329de6d2
		!Pondering-EBooks Al K Line - [Wildcat Wizard 04] - Angel Eyes (v5.0) (azw3).rar  ::INFO:: 366KB ::HASH:: ba9efe11fd8dce03
		!Pondering-EBooks Al K Line - [Wildcat Wizard 04] - Angel Eyes (epub).rar  ::INFO:: 332KB ::HASH:: 78ae9cae96824a7a
		!Pondering-EBooks Karina Giortz - The Wild in Her Eyes (epub).rar  ::INFO:: 539KB ::HASH:: 47ccf9a6822d347e
		!Pondering-EBooks Martha Keyes - My Wild Heart (azw3).rar  ::INFO:: 675KB ::HASH:: 13ad90436cdbb913
		!Pondering-EBooks Julianna Keyes - Big Wild Love Adventure (retail) (epub).rar  ::INFO:: 631KB ::HASH:: 12820fdaa798cd99
		!Pondering-EBooks J T Hunt - Fine Eyes, Wild Temper (epub).rar  ::INFO:: 352KB ::HASH:: 42610878606d646a
		!Ook Karina Giortz - The Wild in Her Eyes (epub).rar  ::INFO:: 467KB ::HASH:: dc921e2131201d9d
		!Ook Al K Line - [Wildcat Wizard 04] - Angel Eyes (epub).rar  ::INFO:: 278KB ::HASH:: fc37a4b1ed8d9234
		!Ook Camiel Rollins - [Wild Night Dreaming 01] - Mr Blue Eyes (epub).rar  ::INFO:: 121KB ::HASH:: 8817db2be0b94901
		!Ook J T Hunt - Fine Eyes, Wild Temper (epub).rar  ::INFO:: 352KB ::HASH:: a26ccaf683cb24f9
		!Ook Julianna Keyes - Big Wild Love Adventure (epub).rar  ::INFO:: 626KB ::HASH:: f82fd88ddca667b1
		!Ook Julianna Keyes - Big Wild Love Adventure (retail) (epub).rar  ::INFO:: 631KB ::HASH:: 286d11dcf6c9139f
		!Ook Martha Keyes - My Wild Heart (azw3).rar  ::INFO:: 673KB ::HASH:: d9a9503e1976fab8
		!peapod Al K Line - [Wildcat Wizard 04] - Angel Eyes (epub).epub  ::INFO:: 278.63KB
		!peapod Al K Line - [Wildcat Wizard 04] - Angel Eyes (v5.0) (azw3).azw3  ::INFO:: 341.55KB
		!peapod Camiel Rollins - [Wild Night Dreaming 01] - Mr Blue Eyes (epub).rar  ::INFO:: 121.64KB
		!peapod Kathy Lyons - [Grizzlies Gone Wild 03] - For the Bear's Eyes Only (epub).epub  ::INFO:: 770.17KB
		!peapod Kathy Lyons - [Grizzlies Gone Wild 03] - For the Bear's Eyes Only (epub).rar  ::INFO:: 776.20KB
		!peapod Martha Keyes - My Wild Heart (azw3).azw3  ::INFO:: 673.36KB
		!peapod Martha Keyes - My Wild Heart (azw3).rar  ::INFO:: 673.46KB
		!peapod Maya Banks - [Eyes (Wild) 01] - Golden Eyes [Samhain] (retail) (epub).epub  ::INFO:: 920.94KB
		!peapod Maya Banks - [Eyes (Wild) 01] - Golden Eyes [Samhain] (retail) (epub).rar  ::INFO:: 931.23KB
		!peapod Maya Banks - [Eyes (Wild) 02] - Amber Eyes [Samhain] (retail) (epub).epub  ::INFO:: 536.88KB
		!peapod Maya Banks - [Eyes (Wild) 02] - Amber Eyes [Samhain] (retail) (epub).rar  ::INFO:: 541.72KB
		!peapod Julianna Keyes - Big Wild Love Adventure (Retail).epub  ::INFO:: 631.27KB
		!peapod Julianna Keyes - Big Wild Love Adventure.epub  ::INFO:: 631.27KB
		!Bsk Al K Line - [Wildcat Wizard 04] - Angel Eyes (epub).epub  ::INFO:: 278.6KB
		!Bsk Al K Line - [Wildcat Wizard 04] - Angel Eyes (epub).rar  ::INFO:: 278.7KB
		!Bsk Al K Line - [Wildcat Wizard 04] - Angel Eyes (v5.0) (azw3).azw3  ::INFO:: 341.6KB
		!Bsk Camiel Rollins - [Wild Night Dreaming 01] - Mr Blue Eyes (epub).rar  ::INFO:: 121.6KB
		!Bsk Daisy Dexter Dobbs - [Wild Winter 13] - Forever Blue Eyes (EC) (pdf).rar  ::INFO:: 311.9KB
		!Bsk Daisy Dexter Dobbs - [Wild Winter 13] - Forever Blue Eyes (html).rar  ::INFO:: 157.4KB
		!Bsk Daisy Dexter Dobbs - [Wild Winter 13] - Forever Blue Eyes (lit).rar  ::INFO:: 119.3KB
		!Bsk Danielle Stewart - [The Barrington Billionaires 02] - Wild Eyes (epub).epub  ::INFO:: 287.0KB
		!Bsk Danielle Stewart - [The Barrington Billionaires 02] - Wild Eyes (epub).rar  ::INFO:: 287.4KB
		!Bsk J T Hunt - Fine Eyes, Wild Temper (epub).rar  ::INFO:: 352.1KB
		!Bsk Julianna Keyes - Big Wild Love Adventure (retail) (epub).rar  ::INFO:: 631.4KB
		!Bsk Martha Keyes - My Wild Heart (azw3).rar  ::INFO:: 673.5KB
		!Bsk Maya Banks - [Eyes (Wild) 01] - Golden Eyes [Samhain] (retail) (epub).rar  ::INFO:: 931.2KB
		!Bsk Maya Banks - [Eyes (Wild) 02] - Amber Eyes [Samhain] (retail) (epub).rar  ::INFO:: 541.7KB
		!Bsk Wendelin Van Draanen - [Sammy Keyes 11] - Sammy Keyes and the Wild Things (retail) (epub).rar  ::INFO:: 606.7KB
		!Bsk Wild Winter - [13] - Forever Blue Eyes - Daisy Dexter Dobbs (EC) (pdf).rar  ::INFO:: 311.9KB
		!DeathCookie Julianna Keyes - Big Wild Love Adventure.epub ::INFO:: 631.27KB
		!DeathCookie Julianna Keyes - Big Wild Love Adventure (Retail).epub ::INFO:: 631.27KB
		!Oatmeal (Wild Winter 13) - Daisy Dexter Dobbs - Forever Blue Eyes (EC).epub ::INFO:: 156.61KB
		!Oatmeal Daisy Dexter Dobbs - (Wild Winter 13) - Forever Blue Eyes.epub ::INFO:: 178.18KB
		!Oatmeal Wendelin Van Draanen - (Sammy Keyes 11) - Sammy Keyes and the Wild Things (retail).epub ::INFO:: 606.73KB
		!Oatmeal Camiel Rollins - (Wild Night Dreaming 01) - Mr Blue Eyes.epub ::INFO:: 123.07KB
		!Oatmeal Maya Banks - (Eyes (Wild) 01) - Golden Eyes (Samhain) (retail).epub ::INFO:: 920.94KB
		!Oatmeal Maya Banks - (Eyes (Wild) 02) - Amber Eyes (Samhain) (retail).epub ::INFO:: 536.88KB
		!Oatmeal Kathy Lyons - (Grizzlies Gone Wild 03) - For the Bear's Eyes Only.epub ::INFO:: 770.17KB
		!Oatmeal Al K Line - (Wildcat Wizard 04) - Angel Eyes (v5.0).epub ::INFO:: 346.15KB
		!Oatmeal Karina Giortz - The Wild in Her Eyes.epub ::INFO:: 466.86KB
		!Oatmeal J T Hunt - Fine Eyes, Wild Temper.epub ::INFO:: 351.99KB
		!Oatmeal Danielle Stewart - Wild Eyes.epub ::INFO:: 287.03KB
		!Oatmeal Martha Keyes - My Wild Heart.epub ::INFO:: 489.52KB
		!Oatmeal Julianna Keyes - Big Wild Love Adventure.epub ::INFO:: 631.27KB
		!Oatmeal Julianna Keyes - Big Wild Love Adventure (Retail).epub ::INFO:: 631.27KB
		!Dumbledore (Wild Winter 13) - Daisy Dexter Dobbs - Forever Blue Eyes (EC).epub
		!Dumbledore Al K Line - (Wildcat Wizard 04) - Angel Eyes (v5.0).epub
		!Dumbledore Al K Line - [Wildcat Wizard 04] - Angel Eyes (epub).epub
		!Dumbledore Al K Line - [Wildcat Wizard 04] - Angel Eyes (v5.0) (azw3).azw3
		!Dumbledore Camiel Rollins - [Wild Night Dreaming 01] - Mr Blue Eyes (epub).epub
		!Dumbledore Daisy Dexter Dobbs - (Wild Winter 13) - Forever Blue Eyes.epub
		!Dumbledore Danielle Stewart - [The Barrington Billionaires 02] - Wild Eyes (epub).epub
		!Dumbledore J T Hunt - Fine Eyes, Wild Temper (epub).epub
		!Dumbledore Julianna Keyes - Big Wild Love Adventure (retail) (epub).epub
		!Dumbledore Julianna Keyes - Big Wild Love Adventure.epub
		!Dumbledore Karina Giortz - The Wild in Her Eyes.epub
		!Dumbledore Kathy Lyons - [Grizzlies Gone Wild 03] - For the Bear's Eyes Only (epub).epub
		!Dumbledore Martha Keyes - My Wild Heart (azw3).azw3
		!Dumbledore Martha Keyes - My Wild Heart.epub
		!Dumbledore Maya Banks - [Eyes (Wild) 01] - Golden Eyes [Samhain] (retail) (epub).epub
		!Dumbledore Maya Banks - [Eyes (Wild) 02] - Amber Eyes [Samhain] (retail) (epub).epub
		!Dumbledore Victoria Lace - [Reyes & Knight 01] - Wild Summer [FR].epub
		!Dumbledore Wendelin Van Draanen - [Sammy Keyes 11] - Sammy Keyes and the Wild Things (retail) (epub).epub
		!Dumbledore Wild Winter - [13] - Forever Blue Eyes - Daisy Dexter Dobbs (EC) (pdf).pdf
		!Firebound %7BEDBF3553D3% Al K. Line - [Wildcat Wizard 04] - Angel Eyes.epub  ::INFO:: 322.13KB
		!Firebound %6EDD57BF8AFA% Danielle Stewart - [Barrington Billionaires, The 02] - Wild Eyes.epub  ::INFO:: 288.14KB
		!Firebound %3BFD3F5C0BFE% Julianna Keyes - Big Wild Love Adventure.epub  ::INFO:: 632.47KB
		!Firebound %G7B69DF32D8D% Martha Keyes - [Regency Shakespeare 02] - My Wild Heart.epub  ::INFO:: 493.44KB
		!FWServer %F7DB3E5B237B% J T Hunt - Fine Eyes, Wild Temper.epub  ::INFO:: 351.99 KB
		!FWServer %6CFFFDB60BFE% Julianna Keyes - Big Wild Love Adventure.epub  ::INFO:: 631.27 KB
		!FWServer %CFFF9FF1EBA8% Karina Giortz - The Wild In Her Eyes.epub  ::INFO:: 466.86 KB
		!FWServer %GDF77BBF5C5D% Van Draanen, Wendelin - Sammy Keyes 11 - Sammy Keyes and the Wild Things - Audiobook.zip  ::INFO:: 393.46 MB
		"""
	return SearchResultsView(
		searchResults: rawResults.components(separatedBy: .newlines)
			.filter { $0.hasPrefix("!") }
			.compactMap { SearchResult(from: $0) },
		onDownload: { _ in })
}
