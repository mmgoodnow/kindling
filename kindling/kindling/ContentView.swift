//
//  ContentView.swift
//  kindling
//
//  Created by Michael Goodnow on 9/9/24.
//

import Network
import SwiftData
import SwiftUI

enum RegistrationStatus {
	case failed
	case ready
	case loading
}

struct ContentView: View {
	@Environment(\.modelContext) private var modelContext
	@AppStorage("ircNick") private var ircNick = "happygolucky"
	@AppStorage("ircServer") private var ircServer = "irc.irchighway.net"
	@AppStorage("ircPort") private var ircPort = 6667
	@AppStorage("ircChannel") private var ircChannel = "#ebooks"

	@State private var downloader: EBookDownloader?
	@State private var reporter = ProgressReporter()
	@State private var downloaderID = UUID()
	@State private var registrationStatus: RegistrationStatus = .loading

	var registrationStatusDotColor: Color {
		switch registrationStatus {
		case .failed:
			Color.red
		case .ready:
			Color.green
		case .loading:
			Color.yellow
		}
	}

	var body: some View {
		NavigationStack {
			if let downloader = downloader {
				MainView(downloader: downloader, reporter: reporter)
					.id(downloaderID)
					.onChange(of: ircNick) { updateDownloader() }
					.onChange(of: ircServer) { updateDownloader() }
					.onChange(of: ircPort) { updateDownloader() }
					.onChange(of: ircChannel) { updateDownloader() }
					.toolbar {
						ToolbarItem {
							Circle()
								.fill(registrationStatusDotColor)
								.frame(width: 10, height: 10)

						}
						ToolbarItem {
							Button(
								action: updateDownloader
							) {
								Image(systemName: "arrow.clockwise")
							}
						}
						ToolbarItem {
							NavigationLink(destination: SettingsView())
							{
								Image(systemName: "gear")
							}
						}
					}
			} else {
				ProgressView()
					.onAppear { updateDownloader() }
			}
		}
	}

	private func updateDownloader() {
		if let oldDownloader = downloader {
			Task {
				try await oldDownloader.cleanup()
			}
		}
		let reporter = ProgressReporter()

		downloader = EBookDownloader(
			ircConnection: IRCConnection(
				connection: NWConnection(
					host: NWEndpoint.Host(ircServer),
					port: NWEndpoint.Port(
						integerLiteral: UInt16(ircPort)),
					using: .tcp
				),
				nickname: ircNick,
				username: ircNick
			),
			ebooksChannel: ircChannel,
			reporter: reporter
		)
		downloaderID = UUID()
		self.reporter = reporter
		Task {
			do {
				registrationStatus = .loading
				try await downloader!.start()
				registrationStatus = .ready
			} catch {
				registrationStatus = .failed
			}
		}
	}
}

#Preview {
	ContentView()
}
