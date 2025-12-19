import SwiftUI

struct SettingsView: View {
	@EnvironmentObject var userSettings: UserSettings

	var body: some View {
		Form {
			Section("Email") {
				TextField(
					"Kindle Email Address",
					text: userSettings.$kindleEmailAddress
				)
			}

			Section("LazyLibrarian") {
				TextField(
					"Base URL (e.g. http://localhost:5299)",
					text: userSettings.$lazyLibrarianURL
				)
				#if os(iOS)
					.textInputAutocapitalization(.never)
					.keyboardType(.URL)
				#endif
				SecureField("API Key", text: userSettings.$lazyLibrarianAPIKey)
					.textContentType(.password)
					#if os(iOS)
						.textInputAutocapitalization(.never)
					#endif
			}

			Section("Podible") {
				TextField("Base URL", text: userSettings.$podibleURL)
					#if os(iOS)
						.textInputAutocapitalization(.never)
						.keyboardType(.URL)
					#endif
			}
t
			Section("IRC") {
				TextField("Server", text: userSettings.$ircServer)
				TextField(
					"Port",
					value: userSettings.$ircPort,
					formatter: portNumberFormatter
				)
				TextField("Channel", text: userSettings.$ircChannel)
				TextField("Nickname", text: userSettings.$ircNick)
				Picker("Search Bot", selection: userSettings.$searchBot) {
					Text("Search").tag("Search")
					Text("SearchOok").tag("SearchOok")
				}.pickerStyle(.menu)
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
	SettingsView()
		.environmentObject(UserSettings())
}
