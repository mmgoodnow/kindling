//
//  ContentView.swift
//  kindling
//
//  Created by Michael Goodnow on 9/9/24.
//

import Network
import SwiftData
import SwiftUI

struct ContentView: View {
	@Environment(\.modelContext) private var modelContext
	var downloader = EBookDownloader(
		ircConnection: IRCConnection(
			connection: NWConnection(
				host: "127.0.0.1",
				port: NWEndpoint.Port(6667),
				using: .tcp
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
