import SwiftUI

struct SettingsView: View {
	@AppStorage("ircNick") private var ircNick = "happygolucky"
	@AppStorage("ircServer") private var ircServer = "irc.irchighway.net"
	@AppStorage("ircPort") private var ircPort = 6667
	@AppStorage("ircChannel") private var ircChannel = "#ebooks"
	@AppStorage("kindleEmailAddress") private var kindleEmailAddress =
		"wengvince_z6xtde@kindle.com"

	var body: some View {
		Form {
			Section("IRC") {
				TextField("Server", text: $ircServer)
				TextField(
					"Port", value: $ircPort,
					formatter: portNumberFormatter
				)
				TextField("Channel", text: $ircChannel)
				TextField("Nickname", text: $ircNick)

			}

			Section("Email") {
				TextField("Kindle Email Address", text: $kindleEmailAddress)
			}
		}.formStyle(.grouped)
			.navigationTitle("Settings")
	}

	private var portNumberFormatter: NumberFormatter {
		let formatter = NumberFormatter()
		formatter.numberStyle = .none
		formatter.minimum = 1
		formatter.maximum = 65535
		return formatter
	}
}

#Preview {
	VStack {
		SettingsView()
	}
}
