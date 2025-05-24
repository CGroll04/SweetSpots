//
//  SpotListView.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-05-10.
//

import SwiftUI
import FirebaseFirestore

struct SpotListView: View {
    @EnvironmentObject private var spotsViewModel: SpotViewModel
    @State private var searchText = ""
    @State private var selectedCategoryFilter: SpotCategory? = nil
    @State private var currentSortOrder: SortOrder = .dateDescending

    enum SortOrder: String, CaseIterable, Identifiable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case nameAscending = "Name (A-Z)"
        case nameDescending = "Name (Z-A)"
        case categoryAscending = "Category (A-Z)"

        var id: String { self.rawValue }
    }

    private var spotsToDisplay: [Spot] {
        var workingSpots = spotsViewModel.spots

        // Apply Category Filter
        if let category = selectedCategoryFilter {
            workingSpots = workingSpots.filter { $0.category == category.displayName }
        }

        // Apply Search Filter
        if !searchText.isEmpty {
            workingSpots = workingSpots.filter { spot in
                spot.name.localizedCaseInsensitiveContains(searchText) ||
                spot.address.localizedCaseInsensitiveContains(searchText) ||
                spot.category.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply Sort Order
        switch currentSortOrder {
        case .dateDescending:
            workingSpots.sort { ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast) }
        case .dateAscending:
            workingSpots.sort { ($0.createdAt?.dateValue() ?? .distantFuture) < ($1.createdAt?.dateValue() ?? .distantFuture) }
        case .nameAscending:
            workingSpots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            workingSpots.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .categoryAscending:
            workingSpots.sort { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
        }
        return workingSpots
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.themeBackground.ignoresSafeArea()

                Group {
                    if spotsViewModel.isLoading && spotsViewModel.spots.isEmpty {
                        VStack {
                            Spacer()
                            ProgressView().scaleEffect(1.5).tint(Color.themePrimary)
                            Text("Loading your Sweet Spots...").font(.headline).foregroundStyle(Color.themeTextSecondary).padding(.top)
                            Spacer()
                        }
                    } else if spotsToDisplay.isEmpty {
                        let description = generateEmptyStateDescription()
                        ThemedContentUnavailableView(
                            title: "No Sweet Spots Found",
                            systemImage: "sparkles.magnifyingglass",
                            description: description
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                if let errorMessage = spotsViewModel.errorMessage {
                                    ErrorBannerView(message: errorMessage)
                                        .padding(.horizontal)
                                }
                                ForEach(spotsToDisplay) { spot in
                                    NavigationLink(value: spot) {
                                        SpotCardView(spot: spot)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .contextMenu {
                                        Button { /* TODO: Implement Edit action */ } label: { Label("Edit Spot", systemImage: "pencil") }
                                        Button(role: .destructive) { deleteSingleSpot(spot) } label: { Label("Delete Spot", systemImage: "trash") }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("My Sweet Spots")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.themeBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if spotsViewModel.isLoading && !spotsViewModel.spots.isEmpty {
                        ProgressView().tint(Color.themePrimary)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    sortMenu
                    filterMenu
                }
            }
            .searchable(text: $searchText, prompt: "Search by name, address, category...")
            .navigationDestination(for: Spot.self) { spot in
                SpotDetailView(spot: spot) // Ensure SpotDetailView is also themed
            }
        }
    }
    
    private func generateEmptyStateDescription() -> String {
        if !searchText.isEmpty {
            return "No spots match your current search or filter. Try different keywords or adjust filters."
        } else if selectedCategoryFilter != nil {
            return "No spots in the selected category. Try a different category or add a new spot!"
        } else {
            return "Tap the '+' tab to add your first memorable spot!"
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter by Category", selection: $selectedCategoryFilter) {
                Text("All Categories").tag(SpotCategory?(nil)) // Option for no filter
                ForEach(SpotCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.systemImageName)
                        .tag(SpotCategory?(category))
                }
            }
        } label: {
            Label("Filter", systemImage: selectedCategoryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Color.themePrimary)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $currentSortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                .foregroundStyle(Color.themePrimary)
        }
    }

    private func deleteSingleSpot(_ spot: Spot) {
        Task {
            await spotsViewModel.deleteSpot(spot)
        }
    }
}

struct SpotCardView: View {
    let spot: Spot

    private var categoryDetails: SpotCategory? {
        SpotCategory.allCases.first { $0.displayName == spot.category }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Category Icon Column
            VStack { // This VStack will contain the icon
                Image(systemName: categoryDetails?.systemImageName ?? SpotCategory.other.systemImageName)
                    .font(.title) // Adjust size of icon as needed
                    .foregroundStyle(Color.white)
                    // No explicit padding on the icon itself if the frame provides enough space
            }
            // Make this VStack a circle
            .frame(width: 50, height: 50) // Make width and height equal for a circle
            .background(Color.themePrimary)
            .clipShape(Circle()) // Clip the background to a circle shape
            .padding(.leading, 12) // Add padding to the left of the circle if desired
            .padding(.trailing, 8)  // Add some spacing between circle and text content


            // Main Content VStack (Text details)
            VStack(alignment: .leading, spacing: 6) {
                Text(spot.name)
                    .font(.system(.headline, design: .rounded)).fontWeight(.bold)
                    .foregroundStyle(Color.themeTextPrimary).lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "mappin").font(.caption).foregroundStyle(Color.themeAccent)
                    Text(spot.address).font(.caption).foregroundStyle(Color.themeTextSecondary).lineLimit(1)
                }

                if let urlString = spot.sourceURL, let url = URL(string: urlString), let host = url.host {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.caption).foregroundStyle(Color.themeAccent)
                        Link(destination: url) {
                            Text(host).font(.caption).foregroundStyle(Color.themePrimary).lineLimit(1)
                        }
                    }
                }
                Spacer()
                Text("Added: \(spot.createdAt?.dateValue() ?? Date(), style: .date)")
                    .font(.caption2).foregroundStyle(Color.themeTextSecondary.opacity(0.8))
            }
            .padding(.vertical, 12) // Vertical padding for the text content
            // No .padding(.leading) here as it's handled by the circle's .padding(.trailing)

            Spacer() // Pushes chevron to the far right
            Image(systemName: "chevron.right").font(.callout).foregroundStyle(Color.themeTextSecondary.opacity(0.7)).padding(.trailing, 12)
        }
        .frame(height: 100) // Adjust overall card height if needed, maybe slightly less now
        .background(Color.themeFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 3)
    }
}

struct ThemedContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.themePrimary)
        } description: {
            if let description = description {
                Text(description)
                    .font(.body).foregroundStyle(Color.themeTextSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.themeBackground.ignoresSafeArea())
    }
}

struct ErrorBannerView: View {
    let message: String
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.white)
            Text(message).font(.footnote).fontWeight(.medium).foregroundStyle(Color.white)
            Spacer()
        }
        .padding().background(Color.themeError).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    SpotListView()
        .environmentObject(SpotViewModel())
        .environmentObject(AuthViewModel())
}
