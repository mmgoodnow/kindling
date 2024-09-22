//
//  ContentView.swift
//  kindling
//
//  Created by Michael Goodnow on 9/9/24.
//

import SwiftData
import SwiftUI
import Network

struct ContentView: View {
	@Environment(\.modelContext) private var modelContext
	var downloader = EBookDownloader(
		ircConnection: IRCConnection(
			connection: NWConnection(
				host: "irc.irchighway.net", port: NWEndpoint.Port(6667), using: .tcp
			),
			nickname: "thankyoukindly",
			username: "thankyoukindly"
		))

	var body: some View {
		NavigationStack {
			MainView(downloader: downloader)
		}
	}
}

#Preview {
	ContentView()
}
