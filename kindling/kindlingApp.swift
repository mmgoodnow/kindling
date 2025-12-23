//
//  kindlingApp.swift
//  kindling
//
//  Created by Michael Goodnow on 9/9/24.
//

import SwiftData
import SwiftUI

@main
struct kindlingApp: App {
  @StateObject private var userSettings = UserSettings()
  var sharedModelContainer: ModelContainer = {
    let schema = Schema([])
    let modelConfiguration = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: false)

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(userSettings)
    }
    .modelContainer(sharedModelContainer)
    #if os(macOS)
      Settings {
        SettingsView()
          .scenePadding()
          .frame(minWidth: 400, minHeight: 400)
          .environmentObject(userSettings)
      }
    #endif
  }
}
