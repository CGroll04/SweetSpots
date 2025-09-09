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

@MainActor
class AddSpotViewModel: ObservableObject {
    @Published var spotForms: [SpotFormState] = [] {
        // This 'didSet' block runs every time a form is added or removed.
        didSet {
            subscribeToFormChanges()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()

    private func subscribeToFormChanges() {
        // First, clear out any old subscriptions to avoid memory leaks.
        cancellables.removeAll()
        
        // For each form in our array...
        spotForms.forEach { formState in
            // ...listen for its 'objectWillChange' signal...
            formState.objectWillChange
                .sink { [weak self] _ in
                    // ...and when it fires, manually trigger the parent's
                    // 'objectWillChange' signal.
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables) // Store the subscription.
        }
    }
    
    // This computed property will now update reliably
    var canSaveAll: Bool {
        !spotForms.isEmpty && spotForms.allSatisfy { $0.isFormValidAndReadyToSave }
    }
}

// MARK: - Step 1: Create the SpotFormState Class
/// This class holds all the data and state for a single, collapsible spot form.
/// It is an ObservableObject to allow SwiftUI views to react to its changes.
@MainActor
class SpotFormState: ObservableObject, Identifiable {
    let id = UUID() // Needed for ForEach loops

    // MARK: - Form Data Properties (Moved from AddSpotView)
    @Published var spotName: String = ""
    @Published var spotAddress: String = ""
    @Published var spotCoordinates: CLLocationCoordinate2D?
    @Published var spotSourceURLInput: String = "Manually Added"
    @Published var selectedCategory: SpotCategory? = nil
    @Published var spotPhoneNumber: String = ""
    @Published var spotWebsiteURLInput: String = ""
    @Published var selectedCollectionIds: Set<String> = []
    @Published var spotNotes: String = ""
    @Published var isFromShare: Bool = false

    // MARK: - Notification Setting Properties (Moved from AddSpotView)
    @Published var wantsNearbyNotificationForThisSpot: Bool = false
    @Published var notificationRadiusForThisSpot: Double = 200.0
    @Published var selectedRadiusPreset: AddSpotView.RadiusPreset = .medium
    @Published var showingCustomRadiusTextField: Bool = false
    @Published var customRadiusText: String = ""

    // MARK: - Individual Form UI State
    @Published var isExpanded: Bool = true
    @Published var searchCompleterVM = SearchCompleterViewModel()
    
    private var originalSpot: Spot? // To track changes in edit mode
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializers
    init() {
        // Creates a blank form for "Add New Manual" mode.
        setupSearchCompleterSubscription()
    }

    init(sourceURL: String, collectionIds: [String] = []) {
        self.spotSourceURLInput = sourceURL
        self.selectedCollectionIds = Set(collectionIds)
        self.isFromShare = true
        setupSearchCompleterSubscription()

    }
    
    init(spot: Spot) {
        self.originalSpot = spot
        
        // Populate all fields from the existing spot object
        self.spotName = spot.name
        self.spotAddress = spot.address
        self.searchCompleterVM.queryFragment = spot.address
        self.spotCoordinates = spot.coordinate
        self.spotSourceURLInput = spot.sourceURL ?? "Manually Added"
        self.selectedCategory = spot.category
        self.spotPhoneNumber = spot.phoneNumber ?? ""
        self.spotWebsiteURLInput = spot.websiteURL ?? ""
        self.selectedCollectionIds = Set(spot.collectionIds) // <-- UPDATED THIS LINE
        self.spotNotes = spot.notes ?? ""
        self.wantsNearbyNotificationForThisSpot = spot.wantsNearbyNotification

        let validRadius = max(50.0, min(50000.0, spot.notificationRadiusMeters))
        self.notificationRadiusForThisSpot = validRadius
        self.selectedRadiusPreset = AddSpotView.RadiusPreset.preset(for: validRadius)

        if self.selectedRadiusPreset == .custom {
            self.customRadiusText = String(Int(validRadius))
            self.showingCustomRadiusTextField = true
        }
        
        self.isFromShare = false
        setupSearchCompleterSubscription()

    }
    
    init(payload: SharedSpotPayload) {
        self.spotName = payload.name
        self.spotAddress = payload.address
        self.spotCoordinates = CLLocationCoordinate2D(latitude: payload.latitude, longitude: payload.longitude)
        self.selectedCategory = SpotCategory(rawValue: payload.category) ?? .other
        self.spotPhoneNumber = payload.phoneNumber ?? ""
        self.spotWebsiteURLInput = payload.websiteURL ?? ""
        self.selectedCollectionIds = [] // Imported spots start with no collections, user adds them
        self.spotNotes = payload.notes ?? ""
        self.spotSourceURLInput = payload.sourceURL ?? "Manually Added" // <-- ADD THIS LINE
        self.isFromShare = true
        setupSearchCompleterSubscription()
    }
    
    private func setupSearchCompleterSubscription() {
            searchCompleterVM.objectWillChange
                .sink { [weak self] _ in
                    // When the inner VM is about to change,
                    // we manually trigger the outer class's change notification.
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

    // MARK: - Computed Validation Properties (Moved from AddSpotView)
    var isValidSpotName: Bool { !spotName.trimmedSafe().isEmpty && spotName.trimmedSafe().count <= 100 }
    var isValidAddress: Bool { spotCoordinates != nil && !spotAddress.trimmedSafe().isEmpty }
    var isValidSourceURL: Bool {
        let trimmed = spotSourceURLInput.trimmedSafe()
        return trimmed.isEmpty || trimmed == "Manually Added" || trimmed.isValidURL
    }
    var isValidPhoneNumber: Bool { spotPhoneNumber.trimmedSafe().isEmpty || ValidationUtils.isValidPhoneNumber(spotPhoneNumber.trimmedSafe()) }
    var isValidWebsiteURL: Bool { spotWebsiteURLInput.trimmedSafe().isEmpty || spotWebsiteURLInput.trimmedSafe().isValidURL }
    var isValidCustomRadius: Bool {
        if selectedRadiusPreset != .custom { return true }
        guard let radius = Double(customRadiusText) else { return false }
        return radius >= 50 && radius <= 50000
    }
    
    var hasChanges: Bool {
        guard let original = originalSpot else { return true } // Always has "changes" for new spots
        if spotName != original.name { return true }
        if spotAddress != original.address { return true }
        if spotSourceURLInput.trimmedSafe() != (original.sourceURL ?? "Manually Added") { return true }
        if selectedCategory != original.category { return true }
        if spotPhoneNumber.trimmedSafe() != (original.phoneNumber ?? "") { return true }
        if spotWebsiteURLInput.trimmedSafe() != (original.websiteURL ?? "") { return true }
        if selectedCollectionIds != Set(original.collectionIds) { return true } // <-- UPDATED THIS LINE
        if spotNotes.trimmedSafe() != (original.notes ?? "") { return true }
        if wantsNearbyNotificationForThisSpot != original.wantsNearbyNotification { return true }
        if !notificationRadiusForThisSpot.isApproximately(original.notificationRadiusMeters) { return true }
        return false
    }
    var validationErrors: [String] {
        var errors: [String] = []
        if !isValidSpotName { errors.append("Spot Name is required.") }
        if !isValidAddress { errors.append("A valid Address is required.") }
        if selectedCategory == nil { errors.append("A Category is required.") }
        if !hasChanges && originalSpot != nil { errors.append("No changes have been made.") }
        // You can add more checks for other fields if you like
        return errors
    }

    var isFormValidAndReadyToSave: Bool {
        // Check the main required fields first
        let hasRequiredFields = isValidSpotName && isValidAddress && selectedCategory != nil
        
        // Check all optional fields
        let hasValidOptionalFields = isValidSourceURL && isValidPhoneNumber && isValidWebsiteURL && isValidCustomRadius
        
        // In edit mode, we also require that there are changes
        if originalSpot != nil { // This implies edit mode
            return hasRequiredFields && hasValidOptionalFields && hasChanges
        }
        
        // In add mode, we don't require changes (it's all new)
        return hasRequiredFields && hasValidOptionalFields
    }
    
    // MARK: - Model Conversion
    /// Builds a `Spot` model object from the current form state.
    func buildSpotModel(with userId: String) -> Spot? {
        guard let coords = spotCoordinates, let category = selectedCategory else { return nil }
        
        let finalSourceURL = (spotSourceURLInput.trimmedSafe() == "Manually Added" || spotSourceURLInput.trimmedSafe().isEmpty) ? nil : spotSourceURLInput.trimmedSafe()
        let finalPhoneNumber = spotPhoneNumber.trimmedSafe().isEmpty ? nil : spotPhoneNumber.trimmedSafe()
        let finalWebsiteURL: String? = {
            let trimmed = spotWebsiteURLInput.trimmedSafe()
            if trimmed.isEmpty { return nil }
            return (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? trimmed : "https://\(trimmed)"
        }()
        let finalNotes = spotNotes.trimmedSafe().isEmpty ? nil : spotNotes.trimmedSafe()
        
        // Use the validated radius value
        var finalRadius = self.notificationRadiusForThisSpot
        if selectedRadiusPreset == .custom, let customRadiusValue = Double(customRadiusText) {
            finalRadius = customRadiusValue
        }
        
        return Spot(
            id: originalSpot?.id, // Keep original ID for updates
            userId: userId,
            name: spotName.trimmedSafe(),
            address: spotAddress.trimmedSafe(),
            latitude: coords.latitude,
            longitude: coords.longitude,
            sourceURL: finalSourceURL,
            category: category,
            phoneNumber: finalPhoneNumber,
            websiteURL: finalWebsiteURL,
            collectionIds: Array(self.selectedCollectionIds), // <-- UPDATED THIS LINE
            wantsNearbyNotification: wantsNearbyNotificationForThisSpot,
            notificationRadiusMeters: finalRadius,
            notes: finalNotes
        )
    }
}


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


    @AppStorage("globalGeofencingEnabled") private var globalGeofencingSystemEnabled: Bool = true
    
    // MARK: - View Presentation & Mode
    @Binding var isPresented: Bool
    let spotToEdit: Spot?
    let prefilledPayload: SharedSpotPayload?
    let prefilledURL: URL?

    enum ViewMode { case addNewManual, addFromShare, addFromPayload, edit }
    private var mode: ViewMode {
        if spotToEdit != nil { return .edit }
        if prefilledPayload != nil { return .addFromPayload } // <-- 3. ADD THIS CHECK
        if prefilledURL != nil { return .addFromShare }
        return .addNewManual
    }
    
    // MARK: - Step 2: Refactor the Main AddSpotView State
    /// The main view now only manages an array of form state objects.
    @StateObject private var viewModel = AddSpotViewModel()


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
        NavigationStack{
                // The main container for our new dynamic form list
                formContentContainer()
                    .layoutPriority(1)
                
                // WebView for context when adding from a shared link
                if mode == .addFromShare, let url = prefilledURL {
                    // Pass the persistent webView from the store into your WebView struct
                    WebView(
                        webView: webViewStore.webView, // <-- Pass the persistent view
                        request: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad),
                        isLoading: $webViewIsLoading,
                        loadingError: $webViewError
                    )
                    .frame(height: showWebView ? 300 : 0)
                    .opacity(showWebView ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showWebView)
                }
            }
            .navigationTitle(navigationTitleString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent() }
            .toolbarBackground(Color.themeBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.themeBackground.ignoresSafeArea())
            .alert(item: $alertInfo) { info in
                Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")) {
                    self.alertInfo = nil; info.onDismiss?()
                })
            }
        .onAppear(perform: setupView)
        // Ensure child views like SpotFormSectionView have access to the collection view model
        .environmentObject(collectionViewModel)
    }

    // MARK: - UI Sections
    
    /// The main form container, now dynamically building sections from the `spotForms` array.
    private func formContentContainer() -> some View {
        Form {
            // Step 4: Use a ForEach loop to create a SpotFormSectionView for each state object.
            ForEach(viewModel.spotForms) { formState in
                SpotFormSectionView(
                    formState: formState, // Pass the object directly
                    index: viewModel.spotForms.firstIndex(where: { $0.id == formState.id }) ?? 0,
                    onRemove: { if viewModel.spotForms.count > 1 { viewModel.spotForms.removeAll(where: { $0.id == formState.id }) } },
                    onFieldFocused: { handleFocus(on: formState.id) },
                    onFieldBlurred: {}
                )
            }

            // Step 5: Add the "Add Another Spot" button, visible only in the correct mode.
            if mode == .addFromShare {
                addAnotherSpotButton()
            }
            
            // The main save button, now at the bottom of the list.
            saveAllButtonSection()
        }
        .scrollContentBackground(.hidden)
    }
    
    private func handleFocus(on focusedFormId: UUID) {
        // Action 1: Hide the WebView
        if showWebView {
            withAnimation {
                showWebView = false
            }
        }

        // Action 2: Collapse all other forms
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
        // Use 'if let' instead of 'guard let'
        if viewModel.spotForms.first != nil {
            // The Section and all its content now go INSIDE the 'if' block
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

        if mode == .addFromShare, prefilledURL != nil {
            ToolbarItem(placement: .principal) {
                Button { withAnimation { showWebView.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showWebView ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        Text(showWebView ? "Hide Post" : "Show Post").font(.caption)
                    }
                }.tint(Color.themeAccent)
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
                Spacer() // This pushes the button to the right side
                
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
        guard viewModel.spotForms.isEmpty else { return }

        let form: SpotFormState

        switch mode {
        case .edit:
            guard let spot = spotToEdit else { fatalError("Edit mode requires a spot.") }
            form = SpotFormState(spot: spot)
            
        case .addFromPayload: // <-- 5. ADD THIS NEW CASE
            guard let payload = prefilledPayload else { fatalError("Payload mode requires a payload.") }
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
        
        isProcessing = true
        
        // Build an array of Spot models from our form states
        let spotsToSave = viewModel.spotForms.compactMap { $0.buildSpotModel(with: userId) }

        if spotsToSave.isEmpty {
            presentAlert(title: "Invalid Data", message: "Please ensure all spots have required fields filled correctly.")
            isProcessing = false
            return
        }
        
        // Handle Edit Mode (only ever one spot)
        if mode == .edit, let spot = spotsToSave.first {
            spotsViewModel.updateSpot(spot) { result in
                handleSaveCompletion(result: result, count: 1)
            }
            return
        }
        
        // Handle Add Modes (can be one or many spots)
        // NOTE: Assumes SpotViewModel has a method `addMultipleSpots`. If not, you'd loop and call `addSpot` here.
        spotsViewModel.addMultipleSpots(spotsToSave) { result in
            handleSaveCompletion(result: result, count: spotsToSave.count)
        }
    }

    private func handleSaveCompletion(result: Result<Void, Error>, count: Int) {
        isProcessing = false
        switch result {
        case .success:
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
        
    private func radiusNumberFormatter() -> NumberFormatter {
           let formatter = NumberFormatter()
           formatter.numberStyle = .decimal
           formatter.minimum = 50    // Min radius
           formatter.maximum = 50000 // Max radius (CLLocationDistance max is huge, but practical limit)
           formatter.maximumFractionDigits = 0 // No decimals for meters usually
           return formatter
       }
    private func triggerScrollHint() {
        scrollHintTimer?.invalidate()
        showScrollHint = true
        scrollHintTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation { self.showScrollHint = false }
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


// MARK: - Step 3: Create the Reusable SpotFormSectionView
/// This view represents one collapsible section in the list. It binds to a `SpotFormState` object.
struct SpotFormSectionView: View {
    @ObservedObject var formState: SpotFormState
    let index: Int
    let onRemove: () -> Void
    var onFieldFocused: () -> Void // <-- NEW: Called when a field gets focus
    var onFieldBlurred: () -> Void // <-- NEW: Called when a field loses focus
    
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
       // DELETE the old .onAppear and .alert modifiers
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
                .zIndex(1) // <-- Gives the button priority over the background tap gesture
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
            // Our custom view that LOOKS like a form row. This is what the user sees.
            HStack {
                if let selectedCategory = formState.selectedCategory {
                    // --- STATE: A category IS selected ---
                    Image(systemName: selectedCategory.systemImageName)
                        .foregroundStyle(Color.themePrimary)
                        .frame(width: 20)

                    Text(selectedCategory.displayName)
                        .foregroundStyle(Color.themeTextPrimary)

                } else {
                    // --- STATE: No category is selected (nil) ---
                    Text("Pick a Category")
                        .foregroundStyle(Color.themeTextSecondary) // Use a placeholder color
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())

            // The ACTUAL Picker.
            Picker("Category", selection: $formState.selectedCategory) {
                // The "prompt" is now the first item in the list, with a nil tag.
                Text("Pick a Category").tag(SpotCategory?(nil))

                // The rest of the categories
                ForEach(SpotCategory.allCases) { category in
                    HStack {
                        Image(systemName: category.systemImageName)
                            .padding(.trailing, 4)
                        Text(category.displayName)
                    }
                    .tag(SpotCategory?(category)) // Tag must now be of type SpotCategory?
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
        
        // Search results view remains the same
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
                ForEach(AddSpotView.RadiusPreset.allCases) { Text($0.rawValue).tag($0) }
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
        // The Picker is now a NavigationLink to our new multi-selector view
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
                print("Could not get place details: \(error.localizedDescription)")
                // The address and completion title are already set, so the user still has something
            }
        }
    }
}


// MARK: - Reusable Child Views (Mostly Unchanged)

// Other helper views like ThemedTextField, SearchResultsList, etc., remain the same
// as they were already well-encapsulated. They are included here for completeness.

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
// ScrollHintView (can be fileprivate or internal if used only here)
fileprivate struct ScrollHintView: View {
    var body: some View {
        Text("Scroll for more content")
            .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.black.opacity(0.7)).foregroundColor(.white) // Slightly more opaque
            .clipShape(Capsule())
    }
}
