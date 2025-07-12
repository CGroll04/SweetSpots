//
//  SearchCompleterViewModel.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-19.
//

import SwiftUI
import MapKit
import Combine

@MainActor
class SearchCompleterViewModel: NSObject, ObservableObject {
    enum SearchState: Equatable {
        case idle
        case searching
        case results([MKLocalSearchCompletion])
        case noResults
        case selected
        case error(String)
    }
    
    @Published var searchState: SearchState = .idle
    @Published var queryFragment: String = "" {
        didSet {
            searchSubject.send(queryFragment)
        }
    }
    
    var searchRegion: MKCoordinateRegion?
    
    private let completer = MKLocalSearchCompleter()
    private var searchSubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var lastSearchQuery = ""
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        
        // MARK: - CHANGE 2: Make the pipeline smarter
        /// We now handle all state changes inside the debounced pipeline.
        searchSubject
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main) // Slightly longer debounce can feel better
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }

                // If the query is empty after debouncing, we are idle.
                if query.isEmpty {
                    self.searchState = .idle
                    self.completer.cancel()
                    return
                }
                
                // *** THIS IS THE KEY ***
                // Set the state to .searching *after* the user has paused typing.
                self.searchState = .searching
                self.performSearch(query)
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(_ query: String) {
        lastSearchQuery = query
        
        // This logic can be slightly simplified now
        // if query.isEmpty is handled in the pipeline
        
        if let region = searchRegion {
            completer.region = region
        }
        
        completer.queryFragment = query
    }
    
    func clearSearch() {
        queryFragment = ""
    }
    
    func select(completion: MKLocalSearchCompletion) {
        searchState = .selected
        completer.cancel()
    }
    
    func getPlaceDetails(for completion: MKLocalSearchCompletion) async throws -> PlaceDetails {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        let response = try await search.start()
        
        guard let mapItem = response.mapItems.first else {
            throw PlaceDetailsError.noDetailsFound
        }
        
        return PlaceDetails(
            fullAddress: formatAddress(from: mapItem),
            coordinates: mapItem.placemark.coordinate,
            phoneNumber: mapItem.phoneNumber,
            websiteURL: mapItem.url
        )
    }
    
    private func formatAddress(from mapItem: MKMapItem) -> String {
        let placemark = mapItem.placemark
        var components: [String] = []
        
        if let name = mapItem.name, name != placemark.name {
            components.append(name)
        }
        
        if let street = placemark.thoroughfare {
            if let number = placemark.subThoroughfare {
                components.append("\(number) \(street)")
            } else {
                components.append(street)
            }
        }
        
        if let city = placemark.locality {
            components.append(city)
        }
        
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        
        if let postalCode = placemark.postalCode {
            components.append(postalCode)
        }
        
        return components.joined(separator: ", ")
    }
}

// MARK: - MKLocalSearchCompleterDelegate
extension SearchCompleterViewModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            // Only update if this is still the current search
            guard completer.queryFragment == lastSearchQuery else { return }
            
            if completer.results.isEmpty {
                searchState = .noResults
            } else {
                searchState = .results(completer.results)
            }
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            // Only update if this is still the current search
            guard completer.queryFragment == lastSearchQuery else { return }
            
            if let error = error as? MKError {
                switch error.code {
                case .placemarkNotFound:
                    searchState = .noResults
                case .serverFailure, .loadingThrottled:
                    searchState = .error("Search service temporarily unavailable")
                default:
                    searchState = .error("Search failed. Please try again.")
                }
            } else {
                searchState = .error("An error occurred during search")
            }
        }
    }
}

// MARK: - Supporting Types
struct PlaceDetails {
    let fullAddress: String
    let coordinates: CLLocationCoordinate2D
    let phoneNumber: String?
    let websiteURL: URL?
}

enum PlaceDetailsError: LocalizedError {
    case noDetailsFound
    
    var errorDescription: String? {
        switch self {
        case .noDetailsFound:
            return "Could not find details for this location"
        }
    }
}

// MARK: - Extensions
extension MKLocalSearchCompletion: @retroactive Identifiable {
    public var id: String {
        "\(title)-\(subtitle)"
    }
    
    var fullDescription: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}
