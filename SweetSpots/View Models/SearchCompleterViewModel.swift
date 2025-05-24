//
//  SearchCompleterViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-19.
//

import SwiftUI
import MapKit
import Combine

@MainActor // Ensures all @Published properties are updated on the main thread
class SearchCompleterViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var queryFragment: String = ""
    @Published var searchResults: [MKLocalSearchCompletion] = []
    
    // This will now be the primary way to know if a selection has been made.
    // When this is set, the UI should reflect the selection and typically hide the search results list.
    @Published var selectedCompletion: MKLocalSearchCompletion? = nil
    
    // Controls visibility of the search results list.
    // It should be true when the user is actively typing and there are results,
    // and false if the query is empty or a selection has been made.
    @Published var isShowingResults: Bool = false

    private var searchCompleter = MKLocalSearchCompleter()
    private var currentSearchCancellable: AnyCancellable? // To cancel ongoing MKLocalSearch if a new one starts
    private var queryFragmentCancellable: AnyCancellable?

    var searchRegion: MKCoordinateRegion = MKCoordinateRegion(.world) { // Default to world, can be updated
        didSet {
            searchCompleter.region = searchRegion
        }
    }

    override init() {
        super.init()
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        searchCompleter.region = self.searchRegion // Set initial region

        // Debounce search query and manage results visibility
        queryFragmentCancellable = $queryFragment
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                guard let self = self else { return }

                if newQuery.isEmpty {
                    self.searchResults = []
                    self.isShowingResults = false
                    // If query becomes empty, and there was a selection, user might be clearing it.
                    // Consider if selectedCompletion should also be cleared here or handled by UI.
                    // For now, let's assume UI handles clearing selectedCompletion if needed.
                } else if self.selectedCompletion != nil && newQuery == self.selectedCompletion?.titleWithSubtitle() {
                    // If the query matches the selected completion, don't re-search or show results.
                    // This prevents the list from reappearing if the user taps back into the field.
                    self.isShowingResults = false
                }
                else {
                    // User is typing a new query or has modified a previous selection.
                    if self.selectedCompletion != nil && newQuery != self.selectedCompletion?.titleWithSubtitle() {
                        // If the query fragment no longer matches the selected completion,
                        // it means the user is editing the search field after making a selection.
                        // We should clear the previous selection to allow for a new search.
                        self.selectedCompletion = nil
                    }
                    self.searchCompleter.queryFragment = newQuery
                    // isShowingResults will be updated by completerDidUpdateResults or completerDidFail
                }
            }
    }

    // MARK: - MKLocalSearchCompleterDelegate
    // Executed on a non-main thread, so dispatch UI updates to @MainActor
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            // Only update if the query fragment still makes sense (e.g., not empty)
            // and if a selection hasn't already been made that matches the current query.
            if !self.queryFragment.isEmpty && self.selectedCompletion == nil {
                self.searchResults = completer.results
                self.isShowingResults = !completer.results.isEmpty
            } else if self.selectedCompletion != nil {
                // If a selection is made, results should typically be hidden.
                self.isShowingResults = false
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            print("Search completer failed with error: \(error.localizedDescription)")
            self.searchResults = []
            self.isShowingResults = false
        }
    }

    // MARK: - Place Details Fetching
    func getPlaceDetails(for completion: MKLocalSearchCompletion, callback: @escaping (_ fullAddress: String?, _ coordinates: CLLocationCoordinate2D?) -> Void) {
        // Cancel any previous search for place details
        currentSearchCancellable?.cancel()

        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        // Store the cancellable for the new search operation
        // Though MKLocalSearch.start doesn't directly return a Combine publisher,
        // this pattern is useful if you were using Combine for the network call.
        // For MKLocalSearch, cancellation is implicit if the 'search' object is deallocated
        // or if you manually manage 'search.cancel()' if needed (not typical for single use).

        search.start { response, error in
            // Ensure callback is on the main thread if it updates UI,
            // though this function is already @MainActor, so its completion should be too.
            Task { @MainActor in
                if let error = error {
                    print("Error getting place details for '\(completion.title)': \(error.localizedDescription)")
                    callback(nil, nil)
                    return
                }
                guard let mapItem = response?.mapItems.first else {
                    print("No map item found for '\(completion.title)'")
                    callback(nil, nil)
                    return
                }

                let placemark = mapItem.placemark
                var addressComponents: [String] = []

                if let name = placemark.name, name != completion.title, !completion.title.contains(name) {
                     // Sometimes placemark.name is more specific or different from completion.title
                     // Use with caution, as completion.title is often what the user expects.
                     // For now, let's prioritize building from components.
                }
                
                // Build address string more robustly
                if let streetNumber = placemark.subThoroughfare { addressComponents.append(streetNumber) }
                if let streetName = placemark.thoroughfare { addressComponents.append(streetName) }
                
                let line1 = addressComponents.joined(separator: " ")
                addressComponents.removeAll()

                if let city = placemark.locality { addressComponents.append(city) }
                if let state = placemark.administrativeArea { addressComponents.append(state) }
                if let postalCode = placemark.postalCode { addressComponents.append(postalCode) }
                // if let country = placemark.country { addressComponents.append(country) } // Optional

                var line2 = addressComponents.joined(separator: ", ")
                if let firstSpaceIndex = line2.firstIndex(of: " "), line2.distance(from: line2.startIndex, to: firstSpaceIndex) > 2 /* avoid splitting zip like "90 210" */ {
                     // This is a simple attempt to format, might need more robust postal address formatting.
                     line2 = addressComponents.reduce("") { result, component in
                         if result.isEmpty { return component }
                         if component.count <= 2 && result.last?.isLetter == true { // e.g., State "CA"
                             return result + " " + component
                         }
                         return result + ", " + component
                     }
                }


                var fullAddress: String
                if !line1.isEmpty && !line2.isEmpty {
                    fullAddress = "\(line1), \(line2)"
                } else if !line1.isEmpty {
                    fullAddress = line1
                } else if !line2.isEmpty {
                    fullAddress = line2
                } else {
                    // Fallback to the completion's title and subtitle
                    fullAddress = completion.title
                    if !completion.subtitle.isEmpty && completion.subtitle != completion.title {
                        fullAddress += ", \(completion.subtitle)"
                    }
                }
                
                callback(fullAddress.trimmingCharacters(in: .whitespacesAndNewlines), mapItem.placemark.coordinate)
            }
        }
    }
}
