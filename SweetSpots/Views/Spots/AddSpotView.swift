//
//  AddSpotView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI
import MapKit
import FirebaseCore
import Combine
import CoreLocation
import os.log

struct AddSpotViewAlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var isSuccess: Bool = false
    var onDismiss: (() -> Void)? = nil
    var autoDismissDelay: Double? = nil
}

// MARK: - Main View
struct AddSpotView: View {
    // MARK: - Environment & State Objects
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var collectionViewModel: CollectionViewModel
    
    @StateObject private var webViewStore = WebViewStore()
    @State private var showingWebSheet = false
    
    private let logger = Logger(subsystem: "com.charliegroll.sweetspots", category: "SpotViewModel")

    @AppStorage("globalGeofencingEnabled") private var globalGeofencingSystemEnabled: Bool = true
    @AppStorage("hasSeenHidePostHint") private var hasSeenHidePostHint: Bool = false
    
    // MARK: - View Presentation & Mode
    @Binding var isPresented: Bool
    let spotToEdit: Spot?
    let prefilledPayload: SharedSpotPayload?
    let prefilledURL: URL?

    enum ViewMode { case addNewManual, addFromShare, addFromPayload, edit }
    private var mode: ViewMode {
        if spotToEdit != nil { return .edit }
        if prefilledPayload != nil { return .addFromPayload }
        if prefilledURL != nil { return .addFromShare }
        return .addNewManual
    }
    
    private var sourceURLForPreview: URL? {
        if let url = prefilledURL {
            return url // For .addFromShare mode
        }
        if let payload = prefilledPayload, let urlString = payload.sourceURL {
            return URL(string: urlString) // For .addFromPayload mode
        }
        return nil
    }
    
    /// The main view now only manages an array of form state objects.
    @StateObject private var viewModel = AddSpotViewModel()
    
    @AppStorage(TutorialKeys.hasSeenAddSpotTips) private var hasSeenAddSpotTips: Bool = false
    @State private var showAddressTip: Bool = false
    @State private var showNotifyTip: Bool = false


    // MARK: - UI & Processing State
    @State private var isProcessing: Bool = false
    @State private var alertInfo: AddSpotViewAlertInfo? = nil
    @State private var showingNewCollectionSheet: Bool = false
    @State private var activeFormId: UUID? = nil
    @State private var viewUpdater = UUID()

    // WebView State (Only for .addFromShare mode)
    @State private var showWebView: Bool = true
    @State private var webViewIsLoading: Bool = false
    @State private var webViewError: Error? = nil
    
    @State private var showScrollHint: Bool = false
    @State private var scrollHintTimer: Timer?

    enum FormField: Hashable { case name, search, url, phone, website, customRadius }

    // MARK: - Computed Properties
    private var navigationTitleString: String {
        switch mode {
        case .addNewManual: return "Add New SweetSpot"
        case .addFromShare: return "New SweetSpot from Share"
        case .addFromPayload: return "Add Shared SweetSpot"
        case .edit: return "Edit SweetSpot"
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            // Create a container for your content
            VStack(spacing: 0) {
                formContentContainer()
                    .layoutPriority(1)
                
                // WebView for context
                if mode == .addFromShare, let url = prefilledURL{
                    // Check if the URL is from a known problematic source like TikTok
                    let host = url.host?.lowercased() ?? ""
                    let isProblematicSource = host.contains("tiktok.com") || host.contains("youtube.com")
                    
                    // This container holds the web preview or the button
                    VStack {
                        if isProblematicSource {
                            // Show a button for TikTok instead of the broken WebView
                            Button(action: {
                                showingWebSheet = true
                            }) {
                                HStack {
                                    Text("Tap to view post")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Material.regular)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding()
                        } else {
                            // For other sites like Instagram, the existing WebView still works
                            WebView(
                                webView: webViewStore.webView,
                                request: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad),
                                isLoading: $webViewIsLoading,
                                loadingError: $webViewError
                            )
                        }
                    }
                    .frame(height: showWebView ? (isProblematicSource ? 100 : 300) : 0)
                    .opacity(showWebView ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showWebView)
                }
            }
            // Apply modifiers to the content INSIDE the NavigationStack
            .navigationTitle(navigationTitleString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent() }
            .toolbarBackground(Color.themeBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.themeBackground.ignoresSafeArea())
        }
        // These modifiers are for the whole view, so they stay outside
        .alert(item: $alertInfo) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")) {
                self.alertInfo = nil; info.onDismiss?()
            })
        }
        .sheet(isPresented: $showingWebSheet) {
            if let url = prefilledURL {
                SafariView(url: url)
            }
        }
        .onAppear(perform: setupView)
        .environmentObject(collectionViewModel)
    }

    // MARK: - UI Sections
    
    /// The main form container, now dynamically building sections from the `spotForms` array.
    private func formContentContainer() -> some View {
        Form {
            if let senderName = viewModel.spotForms.first?.senderName, !senderName.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                        Text("Shared by \(senderName)")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            
            ForEach(viewModel.spotForms) { formState in
                SpotFormSectionView(
                    formState: formState, // Pass the object directly
                    index: viewModel.spotForms.firstIndex(where: { $0.id == formState.id }) ?? 0,
                    onRemove: { if viewModel.spotForms.count > 1 { viewModel.spotForms.removeAll(where: { $0.id == formState.id }) } },
                    onFieldFocused: { handleFocus(on: formState.id) },
                    onFieldBlurred: {},
                    showAddressTip: $showAddressTip,
                    showNotifyTip: $showNotifyTip
                )
            }

            if mode == .addFromShare {
                addAnotherSpotButton()
            }
            
            // The main save button, now at the bottom of the list.
            saveAllButtonSection()
        }
        .scrollContentBackground(.hidden)
    }
    
    private func handleFocus(on focusedFormId: UUID) {
        if showWebView {
            withAnimation {
                showWebView = false
            }
        }

        guard activeFormId != focusedFormId else { return } // Don't do work if already active

        self.activeFormId = focusedFormId
        
        withAnimation(.snappy(duration: 0.3)) {
            for i in viewModel.spotForms.indices {
                // Set isExpanded to true if it's the focused form, false otherwise
                viewModel.spotForms[i].isExpanded = (viewModel.spotForms[i].id == focusedFormId)
            }
        }
    }
    
    @ViewBuilder
    private func addAnotherSpotButton() -> some View {
        Section {
            Button(action: addForm) {
                HStack {
                    Spacer()
                    Label("Add Another Spot from this Post", systemImage: "plus.circle.fill")
                        .font(.headline)
                    Spacer()
                }
            }
            .tint(Color.themeAccent)
        }
    }
    
    @ViewBuilder
    private func saveAllButtonSection() -> some View {
        if viewModel.spotForms.first != nil {
            Section {
                Button(action: handleSave) {
                    HStack {
                        Spacer()
                        if isProcessing {
                            ProgressView().tint(Color.themeButtonText)
                            Text(mode == .edit ? "Updating..." : "Saving...").padding(.leading, 8)
                        } else {
                            let title = (mode == .addFromShare && viewModel.spotForms.count > 1) ? "Save All \(viewModel.spotForms.count) Spots" : (mode == .edit ? "Update SweetSpot" : "Save SweetSpot")
                            Text(title)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .disabled(!viewModel.canSaveAll || isProcessing)
                .listRowBackground(viewModel.canSaveAll ? Color.themePrimary : Color.themePrimary.opacity(0.6))
                .foregroundStyle(Color.themeButtonText)
                .fontWeight(.semibold)

                if !viewModel.canSaveAll && !isProcessing {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.spotForms.first?.validationErrors ?? [], id: \.self) { error in
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text(error)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                    .animation(.easeInOut, value: viewModel.canSaveAll)
                }
            }
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") { isPresented = false }.tint(Color.themeAccent)
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                self.showNotifyTip = false // Reset the sequence
                self.showAddressTip = true // Show the first tip
            } label: {
                Image(systemName: "questionmark.circle")
                    .tint(Color.themeAccent)
            }
        }

        if mode == .addFromShare && prefilledURL != nil {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { withAnimation { showWebView.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showWebView ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        Text(showWebView ? "Hide Post" : "Show Post").font(.caption)
                    }
                }.tint(Color.themeAccent)
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                
                Button("Done") {
                    // Setting the focused field to nil dismisses the keyboard
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
    }
    
    // MARK: - Logic and Actions
    
    /// Step 4 (cont.): Rewritten setupView to initialize the `spotForms` array.
    private func setupView() {
        if let userId = authViewModel.userSession?.uid, collectionViewModel.collections.isEmpty && !collectionViewModel.isLoading {
            collectionViewModel.listenForCollections(userId: userId)
        }
        
        if mode != .edit && !hasSeenAddSpotTips {
            // Use a short delay to let the view settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                self.showAddressTip = true
                self.hasSeenAddSpotTips = true
            }
        }
        
        if mode == .addFromShare && !hasSeenHidePostHint {
            // We use a brief delay to ensure the view is fully presented before showing an alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                presentAlert(
                    title: "Quick Tip",
                    message: "If the social media preview gets in your way, you can tap the 'Hide Post' button in the top-right corner to collapse it.",
                    onDismiss: {
                        // IMPORTANT: Set the flag to true so this never shows again
                        self.hasSeenHidePostHint = true
                    }
                )
            }
        }
        
        guard viewModel.spotForms.isEmpty else { return }

        let form: SpotFormState

        switch mode {
        case .edit:
            guard let spot = spotToEdit else {
                logger.fault("Edit mode requires a spot but was not provided.")
                isPresented = false
                return
            }
            form = SpotFormState(spot: spot)
            
        case .addFromPayload:
            guard let payload = prefilledPayload else {
                logger.fault("Payload mode requires a payload.")
                isPresented = false
                return
            }
            form = SpotFormState(payload: payload)

        case .addFromShare:
            // This case now only handles the old share extension flow
            // The logic for reading from UserDefaults is kept for that, but can be removed if you migrate fully.
            if let url = prefilledURL {
                form = SpotFormState(sourceURL: url.absoluteString)
            } else {
                form = SpotFormState() // Fallback
            }

        case .addNewManual:
            form = SpotFormState()
        }

        if mode != .edit, let userLoc = locationManager.userLocation {
            form.searchCompleterVM.searchRegion = MKCoordinateRegion(
                center: userLoc.coordinate,
                latitudinalMeters: 100_000, longitudinalMeters: 100_000
            )
        }

        viewModel.spotForms.append(form)
    }

    /// Step 5 (cont.): Creates a new form state object and adds it to the array.
    private func addForm() {
        guard let url = prefilledURL else { return }
        // Pre-populate with the same source URL and collection if one was selected
        let lastCollectionIds = viewModel.spotForms.last?.selectedCollectionIds ?? []
        let newForm = SpotFormState(sourceURL: url.absoluteString, collectionIds: Array(lastCollectionIds))
        
        if let userLoc = locationManager.userLocation {
            newForm.searchCompleterVM.searchRegion = MKCoordinateRegion(center: userLoc.coordinate, latitudinalMeters: 100000, longitudinalMeters: 100000)
        }
        
        withAnimation {
            viewModel.spotForms.append(newForm)
        }
    }

    /// Step 4 (cont.): Rewritten save logic to handle an array of forms.
    private func handleSave() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) // Dismiss keyboard
        
        guard let userId = authViewModel.userSession?.uid else {
            presentAlert(title: "Not Logged In", message: "You must be signed in to save spots.")
            return
        }
        
        if mode != .edit {
            for form in viewModel.spotForms {
                let normalizedAddress = form.spotAddress.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if spotsViewModel.spots.contains(where: {
                    $0.address.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedAddress
                }) {
                    presentAlert(title: "Duplicate Spot", message: "A spot with the address '\(form.spotAddress)' already exists in your library.")
                    return // Stop the save process
                }
            }
        }
        
        isProcessing = true
        
        // Build an array of Spot models from our form states
        let spotsToSave = viewModel.spotForms.compactMap { $0.buildSpotModel(with: userId) }

        if spotsToSave.isEmpty {
            presentAlert(title: "Invalid Data", message: "Please ensure all spots have required fields filled correctly.")
            isProcessing = false
            return
        }
        
        let isFirstSpotAdd = mode != .edit && spotsViewModel.spots.isEmpty
        
        // Handle Edit Mode (only ever one spot)
        if mode == .edit, let spot = spotsToSave.first {
            spotsViewModel.updateSpot(spot) { result in
                handleSaveCompletion(result: result, count: 1, isFirstSpotAdd: false)
            }
            return
        }
        
        // Handle Add Modes (can be one or many spots)
        spotsViewModel.addMultipleSpots(spotsToSave) { result in
            handleSaveCompletion(result: result, count: spotsToSave.count, isFirstSpotAdd: isFirstSpotAdd)
        }
    }

    private func handleSaveCompletion(result: Result<Void, Error>, count: Int, isFirstSpotAdd: Bool) {
        isProcessing = false
        switch result {
        case .success:
            self.logger.info("Successfully saved \(count) spot(s).")
            if isFirstSpotAdd {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    // Post a notification that SpotListView/SpotCardView will listen for
                    NotificationCenter.default.post(name: .userAddedFirstSpot, object: nil)
                }
            }
            
            // Sync geofences after a successful save
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000) // Brief delay for DB propagation
                locationManager.synchronizeGeofences(forSpots: spotsViewModel.spots, globallyEnabled: globalGeofencingSystemEnabled)
            }
            
            presentAlert(
                title: "Success!",
                message: "\(count) spot\(count > 1 ? "s" : "") saved.",
                isSuccess: true,
                autoDismissDelay: 1.5,
                onDismiss: { self.isPresented = false }
            )
            
        case .failure(let error):
            self.logger.error("Failed to save \(count) spot(s): \(error.localizedDescription)")
            presentAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }
    
    // MARK: - UI Helpers
    private func presentAlert(title: String, message: String, isSuccess: Bool = false, autoDismissDelay: Double? = nil, onDismiss: (() -> Void)? = nil) {
        // Create the alert info. It will have its own unique ID.
        let newAlert = AddSpotViewAlertInfo(title: title, message: message, isSuccess: isSuccess, onDismiss: onDismiss, autoDismissDelay: autoDismissDelay)
        self.alertInfo = newAlert // Set the state to display this alert
        
        if let delay = autoDismissDelay, isSuccess {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.alertInfo?.id == newAlert.id {
                    self.alertInfo = nil // This dismisses the alert
                    onDismiss?()         // Call the original onDismiss action if it was provided
                }
            }
        }
    }
        
    
    private func triggerScrollHint() {
        scrollHintTimer?.invalidate()
        showScrollHint = true
        scrollHintTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation { self.showScrollHint = false }
        }
    }
    
}


// MARK: - Reusable Child Views

// ScrollHintView 
fileprivate struct ScrollHintView: View {
    var body: some View {
        Text("Scroll for more content")
            .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.black.opacity(0.7)).foregroundColor(.white) // Slightly more opaque
            .clipShape(Capsule())
    }
}
