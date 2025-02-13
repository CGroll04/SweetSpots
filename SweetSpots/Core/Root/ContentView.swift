//
//  ContentView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-02-09.
//

import SwiftUI

struct ContentView: View {
    
    @State var selection = 1
    
    var body: some View {
        TabView(selection: $selection) {
            
            Tab("List", systemImage: "list.bullet", value: 0) {
                    ListView()
            }
            
            Tab("Map", systemImage: "map", value: 1) {
                    MapView()
            }
            Tab("Settings", systemImage: "gearshape", value: 2) {
                    SettingsView()
            }
        }

    }
}

#Preview {
    ContentView()
}
