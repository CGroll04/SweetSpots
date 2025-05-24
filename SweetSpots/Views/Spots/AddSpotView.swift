//
//  AddSpotView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI
import MapKit

struct AddSpotView: View {
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @StateObject private var searchCompleterVM = SearchCompleterViewModel()
    
    @Binding var selectedTab: Int // Assuming this is still an Int from MainTabView
    
    @State private var spotName = ""
    @State private var spotAddress = ""
    @State private var spotCoordinates: CLLocationCoordinate2D?
    @State private var spotURL = ""
    @State private var selectedCategory: SpotCategory = .other // Default category
    
    @State private var isSaving = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    @FocusState private var focusedField: Field?
    
    private enum Field: Hashable { // Made Hashable for @FocusState
        case name, search, url, category
    }
    
    private var canSave: Bool {
        !spotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        spotCoordinates != nil &&
        searchCompleterVM.selectedCompletion != nil && // Ensures a location was picked from search
        !isSaving
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThemedTextField(title: "Spot Name", text: $spotName, systemImage: "pencil.line")
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .search }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        ThemedTextField(title: "Search for a place...", text: $searchCompleterVM.queryFragment, systemImage: "magnifyingglass")
                            .focused($focusedField, equals: .search)
                            .submitLabel(.done) // Or .search
                            .onSubmit { focusedField = nil } // Or trigger search if you prefer
                            .onChange(of: searchCompleterVM.queryFragment) { _, newValue in
                                handleSearchChange(newValue)
                            }
                        
                        if searchCompleterVM.isShowingResults && !searchCompleterVM.searchResults.isEmpty {
                            SearchResultsList(
                                results: searchCompleterVM.searchResults,
                                onSelect: handleSearchSelection
                            )
                        }
                        
                        if searchCompleterVM.selectedCompletion != nil && !spotAddress.isEmpty {
                            SelectedLocationView(address: spotAddress, iconName: "mappin.circle.fill")
                        }
                    }
                    
                    ThemedTextField(title: "Source URL (Optional)", text: $spotURL, systemImage: "link")
                        .focused($focusedField, equals: .url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(SpotCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.systemImageName)
                                .tag(category)
                        }
                    }
                    .tint(Color.themePrimary) // Color for the picker's chevron/accent
                    .focused($focusedField, equals: .category)

                } header: {
                    Text("Spot Details")
                        .font(.subheadline)
                        .foregroundStyle(Color.themeTextSecondary)
                } footer: {
                    if !canSave && !spotName.isEmpty && spotCoordinates == nil {
                        Text("Please select a location from the search results to enable saving.")
                            .font(.caption)
                            .foregroundStyle(Color.themeError)
                    }
                }
                
                Section {
                    Button {
                        hideKeyboard()
                        Task { await saveSpot() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView().tint(Color.themeButtonText)
                                Text("Saving...").padding(.leading, 8)
                            } else {
                                Text("Save Sweet Spot")
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(!canSave)
                    .listRowBackground(canSave ? Color.themePrimary : Color.themePrimary.opacity(0.5))
                    .foregroundStyle(Color.themeButtonText)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("Add New Spot")
            .navigationBarTitleDisplayMode(.inline) // Or .large
            .toolbarBackground(Color.themeBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.themeBackground.ignoresSafeArea()) // Set overall background
            .scrollContentBackground(.hidden) // Makes Form background transparent to show Color.themeBackground
            .task { setupSearchRegion() }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func setupSearchRegion() {
        if let userLocation = locationManager.userLocation {
            searchCompleterVM.searchRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2) // Adjust span as needed
            )
        } else {
            searchCompleterVM.searchRegion = MKCoordinateRegion(.world)
        }
    }
    
    private func handleSearchChange(_ newValue: String) {
        if newValue.isEmpty {
            resetSearchFieldsButKeepQuery() // Keep query for user to see, but clear results
        } else if let selected = searchCompleterVM.selectedCompletion, newValue != selected.titleWithSubtitle() {
            // User started typing again after selecting a result, so clear previous selection
            searchCompleterVM.selectedCompletion = nil
            spotAddress = ""
            spotCoordinates = nil
        }
    }
    
    private func handleSearchSelection(_ completion: MKLocalSearchCompletion) {
        hideKeyboard()
        searchCompleterVM.selectedCompletion = completion
        searchCompleterVM.queryFragment = completion.titleWithSubtitle() // Update TextField to reflect selection
        
        if spotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            spotName = completion.title // Auto-fill spot name if empty
        }
        
        searchCompleterVM.getPlaceDetails(for: completion) { fullAddress, coordinates in
            self.spotAddress = fullAddress ?? completion.titleWithSubtitle()
            self.spotCoordinates = coordinates
        }
        searchCompleterVM.isShowingResults = false // Hide results list
        focusedField = .url // Move focus to URL or category next
    }
    
    private func saveSpot() async {
        guard let userId = authViewModel.userSession?.uid else {
            presentAlert(title: "Authentication Error", message: "You must be logged in to save a spot.")
            return
        }
        guard let coordinates = spotCoordinates, searchCompleterVM.selectedCompletion != nil else {
            presentAlert(title: "Incomplete Information", message: "Please select a valid location from the search results.")
            return
        }
        
        let nameToSave = spotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressToSave = spotAddress.trimmingCharacters(in: .whitespacesAndNewlines) // Ensure address is also trimmed
        
        isSaving = true
        
        spotsViewModel.addSpot(
            name: nameToSave,
            address: addressToSave,
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            sourceURL: spotURL.trimmingCharacters(in: .whitespacesAndNewlines),
            category: selectedCategory.displayName, // Use the selected category's display name
            userId: userId
        ) { success, errorMessage in
            Task { @MainActor in // Ensure UI updates are on main actor
                isSaving = false
                if success {
                    presentAlert(title: "Success!", message: "'\(nameToSave)' has been saved to your Sweet Spots.")
                    clearForm()
                    selectedTab = 0 // Navigate to the list view (assuming tag 0)
                    // Geofencing setup would typically happen after fetching updated spots
                    // or if the new spot object is returned directly by addSpot.
                    // For now, let the SpotListView's updated list handle it.
                } else {
                    presentAlert(title: "Save Failed", message: errorMessage ?? "An unknown error occurred while saving your spot.")
                }
            }
        }
    }
    
    private func presentAlert(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showingAlert = true
    }
    
    private func clearForm() {
        spotName = ""
        spotURL = ""
        selectedCategory = .other // Reset to default category
        resetSearchFields()
    }
    
    private func resetSearchFields() {
        spotAddress = ""
        spotCoordinates = nil
        searchCompleterVM.queryFragment = ""
        searchCompleterVM.searchResults = []
        searchCompleterVM.selectedCompletion = nil
        searchCompleterVM.isShowingResults = false
    }

    private func resetSearchFieldsButKeepQuery() {
        spotAddress = ""
        spotCoordinates = nil
        // searchCompleterVM.queryFragment remains
        searchCompleterVM.searchResults = []
        searchCompleterVM.selectedCompletion = nil
        searchCompleterVM.isShowingResults = false // Or manage based on queryFragment length
    }
    
    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - Themed TextField
private struct ThemedTextField: View {
    let title: String
    @Binding var text: String
    let systemImage: String? // Optional icon

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.themePrimary)
                    .frame(width: 20)
            }
            TextField(title, text: $text, prompt: Text(title).foregroundColor(Color.themeTextSecondary.opacity(0.7)))
                .foregroundStyle(Color.themeTextPrimary)
        }
        // Add padding and background if you want to style individual text fields like AuthTextField
        // .padding()
        // .background(Color.themeFieldBackground)
        // .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}


// MARK: - Supporting Views (Themed)
private struct SearchResultsList: View {
    let results: [MKLocalSearchCompletion]
    let onSelect: (MKLocalSearchCompletion) -> Void
    
    var body: some View {
        List(results, id: \.self) { completion in
            Button {
                onSelect(completion)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(completion.title)
                        .font(.headline).foregroundStyle(Color.themeTextPrimary)
                    Text(completion.subtitle)
                        .font(.subheadline).foregroundStyle(Color.themeTextSecondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.themeFieldBackground) // Theme list row
        }
        .listStyle(.plain)
        .frame(minHeight: 50, maxHeight: 250) // Consider dynamic height based on content
        .background(Color.themeFieldBackground) // Background for the list container
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePrimary.opacity(0.5), lineWidth: 1) // Themed border
        )
    }
}

private struct SelectedLocationView: View {
    let address: String
    let iconName: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(Color.themePrimary)
            Text(address)
                .font(.caption)
                .foregroundStyle(Color.themeTextSecondary)
                .lineLimit(2) // Allow for slightly longer addresses
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.themeFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themePrimary.opacity(0.3), lineWidth: 0.5))
    }
}

// Extension MKLocalSearchCompletion remains the same

#Preview {
    AddSpotView(selectedTab: .constant(2)) // Tab index for "Add"
        .environmentObject(SpotViewModel())
        .environmentObject(AuthViewModel())
        .environmentObject(LocationManager())
        // Ensure your Color+Extensions are available in previews
}
