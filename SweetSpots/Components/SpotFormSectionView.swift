//
//  SpotFormSectionView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-12.
//

import SwiftUI
import MapKit
import FirebaseCore
import Combine
import CoreLocation
import os.log

/// This view represents one collapsible section in the list. It binds to a `SpotFormState` object.
struct SpotFormSectionView: View {
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SpotViewModel")
    @ObservedObject var formState: SpotFormState
    let index: Int
    let onRemove: () -> Void
    var onFieldFocused: () -> Void
    var onFieldBlurred: () -> Void
    
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    @FocusState private var focusedField: AddSpotView.FormField?
    
    @State private var isShowingAddCollectionAlert = false

    @State private var newCollectionName = ""
    
    var body: some View {
       DisclosureGroup(isExpanded: $formState.isExpanded) {
           formFields
       } label: {
           headerLabel
       }
       .tint(Color.themePrimary)
   }
    
    // The label for the DisclosureGroup, including the name and remove button.
    private var headerLabel: some View {
        HStack {
            Text(formState.spotName.isEmpty ? "New Spot \(index + 1)" : formState.spotName)
                .font(.headline)
                .foregroundColor(.themeTextPrimary)
            
            Spacer()

            if index > 0 {
                Button(action: {
                    // The button's primary action
                    withAnimation { onRemove() }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .padding(4) // Add padding to make the tap target slightly larger
                }
                .buttonStyle(.plain)
                .zIndex(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                formState.isExpanded.toggle()
            }
        }
    }
    
    // The content of the form, with all fields bound to the `formState`.
    @ViewBuilder
    private var formFields: some View {
        // --- Main Details ---
        ThemedTextField(title: "Spot Name*", text: $formState.spotName, systemImage: "pencil.line")
            .focused($focusedField, equals: .name)
            .textInputAutocapitalization(.words)
        if !formState.spotName.isEmpty && !formState.isValidSpotName {
            Text("Spot name max 100 characters.").font(.caption).foregroundColor(.themeError)
        }

        locationSearchAndDisplayView()
        
        ThemedTextField(title: "Source URL", text: $formState.spotSourceURLInput, systemImage: "link")
            .focused($focusedField, equals: .url)
            .disabled(formState.isFromShare) // Disable if it came from share extension
        
        ZStack {
            HStack {
                if let selectedCategory = formState.selectedCategory {
                    Image(systemName: selectedCategory.systemImageName)
                        .foregroundStyle(Color.themePrimary)
                        .frame(width: 20)

                    Text(selectedCategory.displayName)
                        .foregroundStyle(Color.themeTextPrimary)

                } else {
                    Text("Pick a Category")
                        .foregroundStyle(Color.themeTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())

            Picker("Category", selection: $formState.selectedCategory) {
                Text("Pick a Category").tag(SpotCategory?(nil))

                // The rest of the categories
                ForEach(SpotCategory.allCases) { category in
                    HStack {
                        Image(systemName: category.systemImageName)
                            .padding(.trailing, 4)
                        Text(category.displayName)
                    }
                    .tag(SpotCategory?(category))
                }
            }
            .labelsHidden()
            .opacity(0.015)
        }
        
        // --- Optional Details ---
        ThemedTextField(title: "Phone Number", text: $formState.spotPhoneNumber, systemImage: "phone.fill")
            .focused($focusedField, equals: .phone)
        ThemedTextField(title: "Website URL", text: $formState.spotWebsiteURLInput, systemImage: "globe")
            .focused($focusedField, equals: .website)
        
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $formState.spotNotes)
                .frame(height: 100).padding(4).background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4), lineWidth: 1))
        }
        
        // --- Notification Settings ---
        notificationSettings()
        
        // --- Collection Picker ---
        collectionPicker()
    }
    
    // MARK: Section Subviews
    
    @ViewBuilder
    private func locationSearchAndDisplayView() -> some View {
        ZStack(alignment: .trailing) {
            ThemedTextField(
                title: "Address or Place*",
                text: $formState.searchCompleterVM.queryFragment,
                systemImage: "magnifyingglass"
            )
            .focused($focusedField, equals: .search)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.words)
            // This padding is correct, it makes room for our button.
            .padding(.trailing, formState.searchCompleterVM.queryFragment.isEmpty ? 0 : 44)

            // Clear button with proper hit area
            if !formState.searchCompleterVM.queryFragment.isEmpty {
                Button(action: {
                    formState.searchCompleterVM.clearSearch()
                    formState.spotAddress = ""
                    formState.spotCoordinates = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        // 44x44 is Apple's recommended minimum for touch targets.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .zIndex(1)
            }
        }
        
        searchResultsView()
    }
    
    @ViewBuilder
    private func searchResultsView() -> some View {
        Group {
            switch formState.searchCompleterVM.searchState {
            case .idle:
                if formState.spotAddress.isEmpty && focusedField == .search {
                    HStack {
                        Text("Start typing to search for a location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
            case .searching:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 4)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            
            case .loadingDetails:
                HStack {
                    ProgressView()
                        .padding(.trailing, 4)
                    Text("Fetching details...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                
            case .results(let completions):
                SearchResultsList(results: completions) { completion in
                    focusedField = nil // Dismiss keyboard

                    // 1. Set the state to loadingDetails to show a spinner
                    formState.searchCompleterVM.searchState = .loadingDetails
                    
                    let immediateAddress = completion.subtitle.isEmpty
                        ? completion.title
                        : "\(completion.title), \(completion.subtitle)"
                    formState.searchCompleterVM.queryFragment = immediateAddress
                    formState.spotAddress = immediateAddress
                    Task {
                        do {
                            // 2. Try to fetch the details
                            let details = try await formState.searchCompleterVM.getPlaceDetails(for: completion)
                            
                            // 3. On success, update the form and set state to .selected
                            await MainActor.run {
                                let potentialName = details.name.trimmingCharacters(in: .whitespacesAndNewlines)

                                // 2. Only assign it if the form's name is empty AND the potential name isn't.
                                if formState.spotName.isEmpty && !potentialName.isEmpty {
                                    formState.spotName = potentialName
                                }
                                formState.spotAddress = details.fullAddress
                                formState.searchCompleterVM.queryFragment = details.fullAddress
                                formState.spotCoordinates = details.coordinates
                                if formState.spotPhoneNumber.isEmpty { formState.spotPhoneNumber = details.phoneNumber ?? "" }
                                if formState.spotWebsiteURLInput.isEmpty { formState.spotWebsiteURLInput = details.websiteURL?.absoluteString ?? "" }
                                
                                formState.searchCompleterVM.searchState = .selected
                                formState.objectWillChange.send()
                            }
                        } catch {
                            // 4. On failure, update the state to show an error message to the user
                            formState.searchCompleterVM.searchState = .error("Failed to load location details. Please try again.")
                        }
                    }
                }
                
            case .noResults:
                HStack {
                    Image(systemName: "questionmark.folder.fill")
                        .foregroundColor(.secondary)
                    Text("No results found. Try another search.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
            case .selected:
                if !formState.spotAddress.isEmpty {
                    SelectedLocationView(
                        address: formState.spotAddress,
                        iconName: "mappin.circle.fill"
                    )
                }
                
            case .error(let message):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: formState.searchCompleterVM.searchState)
    }

    
    @ViewBuilder
    private func notificationSettings() -> some View {
        Toggle("Notify me when nearby", isOn: $formState.wantsNearbyNotificationForThisSpot).tint(.themePrimary)

        if formState.wantsNearbyNotificationForThisSpot {
            Picker("Notification Distance", selection: $formState.selectedRadiusPreset) {
                ForEach(RadiusPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: formState.selectedRadiusPreset) { _, newPreset in
                if let radius = newPreset.radiusValue {
                    formState.notificationRadiusForThisSpot = radius
                    formState.showingCustomRadiusTextField = false
                } else {
                    formState.showingCustomRadiusTextField = true
                }
            }

            if formState.showingCustomRadiusTextField {
                HStack {
                    Text("Custom (meters):")
                    TextField("50-50000", text: $formState.customRadiusText)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .customRadius)
                }
            }
        }
    }
    
    // A helper to create a display string for the selected collections
    private var collectionsDisplayString: String {
        let selected = collectionViewModel.collections.filter {
            guard let id = $0.id else { return false }
            return formState.selectedCollectionIds.contains(id)
        }

        if selected.isEmpty {
            return "No Collection"
        } else {
            return selected.map { $0.name }.joined(separator: ", ")
        }
    }

    @ViewBuilder
    private func collectionPicker() -> some View {
        NavigationLink {
            MultiCollectionSelectorView(selectedCollectionIds: $formState.selectedCollectionIds)
                .environmentObject(collectionViewModel)
        } label: {
            HStack {
                Text("Collections")
                Spacer()
                Text(collectionsDisplayString)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    
    // MARK: Logic
    private func processSearchSelection(_ completion: MKLocalSearchCompletion) {
        // Update the view model state
        formState.searchCompleterVM.select(completion: completion)
        
        // Pre-fill the name if empty
        if formState.spotName.trimmedSafe().isEmpty {
            formState.spotName = completion.title
        }
        
        // Update address immediately for instant feedback
        formState.spotAddress = completion.fullDescription
        
        // Fetch detailed information
        Task {
            do {
                let details = try await formState.searchCompleterVM.getPlaceDetails(for: completion)
                await MainActor.run {
                    formState.spotAddress = details.fullAddress
                    formState.spotCoordinates = details.coordinates
                    
                    if formState.spotPhoneNumber.isEmpty {
                        formState.spotPhoneNumber = details.phoneNumber ?? ""
                    }
                    if formState.spotWebsiteURLInput.isEmpty {
                        formState.spotWebsiteURLInput = details.websiteURL?.absoluteString ?? ""
                    }
                }
            } catch {
                logger.error("Could not get place details: \(error.localizedDescription)")
                // The address and completion title are already set, so the user still has something
            }
        }
    }
    
    // MARK: - Helpers
    // Enums can remain here as they are tightly coupled to the AddSpotView's UI logic.
    enum RadiusPreset: String, CaseIterable, Identifiable, Hashable {
        case close = "Close (~100m)", medium = "Medium (~200m)", far = "Far (~500m)", custom = "Custom"
        var id: String { rawValue }
        var radiusValue: Double? {
            switch self {
            case .close: return 100.0
            case .medium: return 200.0
            case .far: return 500.0
            case .custom: return nil
            }
        }
        static func preset(for radius: Double) -> RadiusPreset {
            if radius.isApproximately(100.0) { return .close }
            if radius.isApproximately(200.0) { return .medium }
            if radius.isApproximately(500.0) { return .far }
            return .custom
        }
    }
}

private struct ThemedTextField: View {
    let title: String
    @Binding var text: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage = systemImage {
                Image(systemName: systemImage).foregroundStyle(Color.themePrimary).frame(width: 20)
            }
            TextField(title, text: $text, prompt: Text(title).foregroundColor(Color.themeTextSecondary.opacity(0.7)))
                .foregroundStyle(Color.themeTextPrimary)
        }
    }
}

private struct SearchResultsList: View {
    let results: [MKLocalSearchCompletion]
    let onSelect: (MKLocalSearchCompletion) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(results.prefix(10).enumerated()), id: \.element) { index, completion in
                    Button(action: { onSelect(completion) }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(completion.title)
                                .font(.headline)
                                .foregroundStyle(Color.themeTextPrimary)
                                .lineLimit(1)
                            
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.themeTextSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    
                    if index < results.count - 1 {
                        Divider()
                            .padding(.leading)
                    }
                }
            }
        }
        .frame(maxHeight: 300)
        .background(Color.themeFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
}

private struct SelectedLocationView: View {
    let address: String
    let iconName: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName).foregroundStyle(Color.themePrimary)
            Text(address).font(.caption).foregroundStyle(Color.themeTextSecondary).lineLimit(2)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Color.themeFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
