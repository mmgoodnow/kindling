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
	@AppStorage("ircNick") private var ircNick = "happygolucky"
	@AppStorage("ircServer") private var ircServer = "irc.irchighway.net"
	@AppStorage("ircPort") private var ircPort = 6667
	@AppStorage("ircChannel") private var ircChannel = "#ebooks"

	@State private var downloader: EBookDownloader?

	var body: some View {
		NavigationStack {
			if let downloader = downloader {
				MainView(downloader: downloader)
					.onAppear { updateDownloader() }
					.onChange(of: ircNick) { updateDownloader() }
					.onChange(of: ircServer) { updateDownloader() }
					.onChange(of: ircPort) { updateDownloader() }
					.onChange(of: ircChannel) { updateDownloader() }
			} else {
				ProgressView().onAppear { updateDownloader() }
			}
		}
	}

	private func updateDownloader() {
		// Create a new IRCConnection using the updated values
		let connection = IRCConnection(
			connection: NWConnection(
				host: NWEndpoint.Host(ircServer),
				port: NWEndpoint.Port(integerLiteral: UInt16(ircPort)),
				using: .tcp
			),
			nickname: ircNick,
			username: ircNick
		)

		// Create the EBookDownloader using the updated IRCConnection and channel
		self.downloader = EBookDownloader(
			ircConnection: connection,
			ebooksChannel: ircChannel
		)
	}
}

#Preview {
	ContentView()
}
