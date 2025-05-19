//
//  SpotListView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI
import FirebaseFirestore // For Timestamp formatting

struct SpotListView: View {
    @EnvironmentObject var spotsViewModel: SpotViewModel
    @EnvironmentObject var authViewModel: AuthViewModel // To get userId for potential actions

    var body: some View {
        NavigationStack {
            Group {
                if spotsViewModel.isLoading && spotsViewModel.spots.isEmpty {
                    ProgressView("Loading Spots...")
                } else if spotsViewModel.spots.isEmpty {
                    VStack {
                        Image(systemName: "figure.outdoor.cycle") // Or any other relevant icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.gray)
                            .padding(.bottom)
                        Text("No Sweet Spots Yet!")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Tap the '+' tab to add your first spot.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else {
                    List {
                        if let errorMessage = spotsViewModel.errorMessage, !spotsViewModel.spots.isEmpty {
                             Section {
                                 Text(errorMessage).foregroundColor(.red)
                             }
                         }
                        ForEach(spotsViewModel.spots) { spot in
                            SpotRow(spot: spot)
                        }
                        .onDelete(perform: deleteSpot)
                    }
                }
            }
            .navigationTitle("My Sweet Spots")
            .toolbar {
                if spotsViewModel.isLoading {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProgressView()
                    }
                }
            }
            // .onAppear { // Data is now fetched in MainTabView
            //     if let userId = authViewModel.userSession?.uid {
            //         spotsViewModel.fetchData(userId: userId)
            //     }
            // }
        }
    }

    private func deleteSpot(at offsets: IndexSet) {
        offsets.map { spotsViewModel.spots[$0] }.forEach { spot in
            spotsViewModel.deleteSpot(spot)
        }
    }
}

// Reusable Row View
struct SpotRow: View {
    let spot: Spot

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.headline)
                if let urlString = spot.sourceURL, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Text(host(from: urlString) ?? urlString)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                } else {
                    Text(spot.address)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Text("Added: \(spot.createdAt?.dateValue() ?? Date(), style: .date)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
            // You could add a small image or icon here if desired
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.accentColor)
        }
        .padding(.vertical, 4)
    }

    private func host(from urlString: String?) -> String? {
        guard let urlString = urlString, let url = URL(string: urlString) else { return nil }
        return url.host
    }
}

struct SpotListView_Previews: PreviewProvider {
    static var previews: some View {
        let spotsVM = SpotViewModel()
        spotsVM.spots = [
            Spot(id: "1", userId: "testUser", name: "Amazing Cafe", address: "123 Main St", latitude: 0, longitude: 0, sourceURL: "https://example.com", createdAt: Timestamp(date: Date())),
            Spot(id: "2", userId: "testUser", name: "Secret Viewpoint", address: "456 Park Ave", latitude: 0, longitude: 0, sourceURL: nil, createdAt: Timestamp(date: Date().addingTimeInterval(-86400)))
        ]
        return SpotListView()
            .environmentObject(spotsVM)
            .environmentObject(AuthViewModel()) // For preview
    }
}
