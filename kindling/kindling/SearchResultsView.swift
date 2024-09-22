import SwiftUI

struct SearchResultsView: View {
	let searchResults: [SearchResult]
	let onDownload: (SearchResult) -> Void  // Callback for download action
	
	var body: some View {
		List(searchResults, id: \.self) { result in
			HStack {
				VStack(alignment: .leading) {
					Text(result.title)
						.font(.headline)  // Main title (e.g., eBook title)
					Text(result.bot)
						.font(.subheadline)  // Subtitle (bot name)
						.foregroundColor(.gray)
					if let hash = result.hash {
						Text(hash)
							.font(.subheadline)  // Subtitle (bot name)
							.foregroundColor(.gray)
					}
				}
				Spacer()
				Button(action: {
					onDownload(result)  // Call the download action when tapped
				}) {
					Text("Download")
						.font(.footnote)
						.foregroundColor(.blue)
				}
			}
			.padding(.vertical, 4)
		}
	}
}
