//
//  ContentView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-02-09.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
                .tabItem{
                    Text("Tab 1")
                }
            
            Text("Hello, world!")
                .tabItem{
                    Text("Tab 2")
                }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
