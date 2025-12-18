//
//  ContentView.swift
//  kindling
//
//  Created by Michael Goodnow on 9/9/24.
//

import SwiftUI

struct ContentView: View {
	var body: some View {
		NavigationStack {
			LazyLibrarianView()
				.toolbar {
					ToolbarItem {
						NavigationLink(destination: SettingsView()) {
							Image(systemName: "gear")
						}
					}
				}
		}
	}
}

#Preview {
	ContentView()
}
