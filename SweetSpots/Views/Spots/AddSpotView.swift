//
//  AddSpotView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI
import MapKit // For MKCoordinateRegion

struct AddSpotView: View {
    @EnvironmentObject var spotsViewModel: SpotViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var locationManager: LocationManager
    @StateObject private var searchCompleterVM = SearchCompleterViewModel()

    @Binding var selectedTab: Int

    @State private var spotName: String = ""
    @State private var spotAddress: String = "" // For display/confirmation after selection
    @State private var spotCoordinates: CLLocationCoordinate2D?
    @State private var spotURL: String = ""

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSaving = false
    
    @FocusState private var isSearchFieldFocused: Bool // To manage focus

    var canSave: Bool {
        !spotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        spotCoordinates != nil &&
        searchCompleterVM.selectedCompletion != nil && // Ensure a selection was made
        !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Spot Details")) {
                    TextField("Spot Name (e.g., Philz Coffee)", text: $spotName)
                    
                    VStack(alignment: .leading) {
                        Text("Place or Address")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("Search here...", text: $searchCompleterVM.queryFragment)
                            .focused($isSearchFieldFocused) // Manage focus state
                            .onChange(of: searchCompleterVM.queryFragment) { oldValue, newValue in
                                // If user clears the text field after making a selection, reset
                                if newValue.isEmpty {
                                    resetSearchFields()
                                } else if searchCompleterVM.selectedCompletion != nil && newValue != searchCompleterVM.selectedCompletion?.titleWithSubtitle() {
                                    // If user types something different after selection, allow new search
                                    searchCompleterVM.selectedCompletion = nil
                                    spotAddress = ""
                                    spotCoordinates = nil
                                }
                            }

                        if searchCompleterVM.isShowingResults && !searchCompleterVM.searchResults.isEmpty {
                            List { // Removed explicit List(searchResults) to use implicit ForEach if needed
                                ForEach(searchCompleterVM.searchResults, id: \.self) { completion in
                                    Button(action: {
                                        searchCompleterVM.selectedCompletion = completion
                                        // Update the TextField with a comprehensive title from completion
                                        searchCompleterVM.queryFragment = completion.titleWithSubtitle()
                                        
                                        // Pre-fill spot name if it's empty or was the same as previous search query
                                        if spotName.isEmpty || spotName == (searchCompleterVM.queryFragment) { // A bit simplified
                                            spotName = completion.title
                                        }
                                        
                                        searchCompleterVM.getPlaceDetails(for: completion) { fullAddress, coordinates in
                                            self.spotAddress = fullAddress ?? completion.titleWithSubtitle()
                                            self.spotCoordinates = coordinates
                                        }
                                        searchCompleterVM.isShowingResults = false
                                        isSearchFieldFocused = false // Dismiss keyboard
                                    }) {
                                        VStack(alignment: .leading) {
                                            Text(completion.title)
                                                .font(.headline)
                                                .foregroundColor(.primary) // Ensure text is visible
                                            Text(completion.subtitle)
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .buttonStyle(.plain) // Use plain button style for list items
                                }
                            }
                            .listStyle(.plain)
                            .frame(minHeight: 50, maxHeight: 250) // Adjust height
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        if searchCompleterVM.selectedCompletion != nil && !spotAddress.isEmpty {
                             HStack {
                                 Image(systemName: "mappin.and.ellipse")
                                     .foregroundColor(.accentColor)
                                 Text(spotAddress)
                                     .font(.caption)
                                     .foregroundColor(.secondary)
                             }
                             .padding(.top, 5)
                        }
                    }
                    
                    TextField("Source URL (Optional)", text: $spotURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }

                Section {
                    Button(action: saveSpot) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView().padding(.trailing, 5)
                                Text("Saving...")
                            } else {
                                Text("Save Sweet Spot")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .navigationTitle("Add New Spot")
            .alert("Add Spot", isPresented: $showAlert, actions: {
                Button("OK") {}
            }, message: {
                Text(alertMessage)
            })
            .onAppear {
                if let userLocation = locationManager.userLocation {
                    searchCompleterVM.searchRegion = MKCoordinateRegion(
                        center: userLocation.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2) // Wider search area initially
                    )
                } else {
                     searchCompleterVM.searchRegion = MKCoordinateRegion(.world)
                }
            }
        }
    }

    private func saveSpot() {
        guard let userId = authViewModel.userSession?.uid else {
            alertMessage = "Error: Not logged in."
            showAlert = true
            return
        }
        guard let coordinates = spotCoordinates, searchCompleterVM.selectedCompletion != nil else {
            alertMessage = "Please select a valid location from the search results."
            showAlert = true
            return
        }

        let nameToSave = spotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressToSave = self.spotAddress // Already set and formatted

        isSaving = true
        spotsViewModel.addSpot(
            name: nameToSave,
            address: addressToSave,
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            sourceURL: spotURL, // ViewModel will handle trimming
            userId: userId
        ) { success, message in
            isSaving = false
            if success {
                alertMessage = "Spot '\(nameToSave)' saved successfully!"
                clearForm()
                selectedTab = 0 // Switch to List view

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if let newSpot = spotsViewModel.spots.first(where: {
                        $0.name == nameToSave && $0.address == addressToSave && $0.id != nil
                    }) {
                        self.locationManager.startMonitoring(spot: newSpot)
                        print("DEBUG: Started monitoring for new spot: \(newSpot.name)")
                    } else {
                        print("DEBUG: Could not find newly added spot (\(nameToSave)) to start geofencing.")
                    }
                }
            } else {
                alertMessage = message ?? "Failed to save spot '\(nameToSave)'. Please try again."
            }
            showAlert = true // Show alert for both success and failure
        }
    }

    private func clearForm() {
        spotName = ""
        resetSearchFields()
        spotURL = ""
    }
    
    private func resetSearchFields() {
        spotAddress = ""
        spotCoordinates = nil
        searchCompleterVM.queryFragment = ""
        searchCompleterVM.searchResults = []
        searchCompleterVM.selectedCompletion = nil
        searchCompleterVM.isShowingResults = false
    }
}

extension MKLocalSearchCompletion {
    // Helper to get a displayable string, as title or subtitle can sometimes be redundant
    func titleWithSubtitle() -> String {
        var displayString = title
        if !subtitle.isEmpty && subtitle != title {
            displayString += ", \(subtitle)"
        }
        return displayString
    }
}

struct AddSpotView_Previews: PreviewProvider {
    static var previews: some View {
        AddSpotView(selectedTab: .constant(2))
            .environmentObject(SpotViewModel())
            .environmentObject(AuthViewModel())
            .environmentObject(LocationManager())
    }
}
