//
//  ContentView.swift
//  kindling
//
//  Created by Michael Goodnow on 9/9/24.
//

import Combine
import Network
import SwiftData
import SwiftUI

struct ContentView: View {
	@Environment(\.modelContext) private var modelContext
	@EnvironmentObject var userSettings: UserSettings
	@State private var downloader: EBookDownloader?
	@State private var stateReporter = StateReporter()
	@State private var downloaderID = UUID()
	@State private var cancellables = Set<AnyCancellable>()

	var registrationStatusDotColor: Color {
		switch stateReporter.state {
		case .idle: Color.gray
		case .failed: Color.red
		case .ready: Color.green
		case .loading: Color.yellow
		}
	}

	var body: some View {
		NavigationStack {
			if let downloader = downloader {
				SearchView(downloader: downloader)
					.id(downloaderID)
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
		let stateReporter = StateReporter()
		let downloader = EBookDownloader(
			ircConnection: IRCConnection(
				connection: NWConnection(
					host: NWEndpoint.Host(userSettings.ircServer),
					port: NWEndpoint.Port(
						integerLiteral: UInt16(userSettings.ircPort)),
					using: .tcp
				),
				nickname: userSettings.ircNick,
				username: userSettings.ircNick,
				stateReporter: stateReporter
			),
			ebooksChannel: userSettings.ircChannel,
			stateReporter: stateReporter
		)
		downloaderID = UUID()
		self.downloader = downloader
		self.stateReporter = stateReporter

		Task {
			try await downloader.start()
		}
	}
}

#Preview {
	ContentView()
}
