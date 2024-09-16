//
//  ContentView.swift
//  kindling
//
//  Created by Michael Goodnow on 9/9/24.
//

import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var inputText: String = "" // A state variable to hold the text input
  
  var body: some View {
    VStack {
      HStack {
        Button(action: { }) {
          Text("Connect to Server")
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        Button(action: {}) {
          Text("Disconnect")
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
      }
      TextField("Enter your text here", text: $inputText)
        .padding()
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .onSubmit {
        }
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
