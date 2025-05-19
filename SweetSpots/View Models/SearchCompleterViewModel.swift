//
//  SearchCompleterViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-19.
//

import SwiftUI
import MapKit
import Combine // For Cancellable

@MainActor // Ensure UI updates are on the main thread
class SearchCompleterViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var queryFragment: String = ""
    @Published var searchResults: [MKLocalSearchCompletion] = []
    @Published var selectedCompletion: MKLocalSearchCompletion? {
        didSet {
            if selectedCompletion != nil {
                isShowingResults = false // Hide results once one is selected
            }
        }
    }
    @Published var isShowingResults: Bool = false // To control visibility of results list

    private var searchCompleter = MKLocalSearchCompleter()
    private var cancellable: AnyCancellable?

    // To prioritize nearby results, we need the user's current region
    var searchRegion: MKCoordinateRegion? {
        didSet {
            searchCompleter.region = searchRegion ?? MKCoordinateRegion(.world)
        }
    }

    override init() {
        super.init()
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest] // Include both

        // Debounce search query
        cancellable = $queryFragment
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main) // Add a small delay
            .removeDuplicates()
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                if newQuery.isEmpty {
                    self.searchResults = []
                    self.isShowingResults = false
                } else {
                    self.searchCompleter.queryFragment = newQuery
                    self.isShowingResults = true // Show results when typing starts
                }
            }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        self.searchResults = completer.results
        self.isShowingResults = !completer.results.isEmpty && !queryFragment.isEmpty
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer failed with error: \(error.localizedDescription)")
        self.searchResults = []
        self.isShowingResults = false
    }

    // Function to get full address and coordinates from a selected completion
    func getPlaceDetails(for completion: MKLocalSearchCompletion, callback: @escaping (String?, CLLocationCoordinate2D?) -> Void) {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, error in
            if let error = error {
                print("Error getting place details: \(error.localizedDescription)")
                callback(nil, nil)
                return
            }
            guard let mapItem = response?.mapItems.first else {
                callback(nil, nil)
                return
            }

            // Construct a full address string
            let placemark = mapItem.placemark
            var addressString = ""
            if let streetNumber = placemark.subThoroughfare { addressString += streetNumber + " " }
            if let streetName = placemark.thoroughfare { addressString += streetName }
            if !addressString.isEmpty { addressString += ", " }
            if let city = placemark.locality { addressString += city }
            if !addressString.isEmpty && placemark.administrativeArea != nil { addressString += ", " }
            if let state = placemark.administrativeArea { addressString += state + " " }
            if let postalCode = placemark.postalCode { addressString += postalCode }
            if addressString.isEmpty { // Fallback if detailed components are missing
                addressString = completion.title
                if !completion.subtitle.isEmpty { addressString += ", " + completion.subtitle }
            }


            callback(addressString.trimmingCharacters(in: .whitespacesAndNewlines), mapItem.placemark.coordinate)
        }
    }
}
