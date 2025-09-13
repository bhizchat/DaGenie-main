//  CreateAdventureVM.swift
//  Handles college / filters selection and fetches AdventureThemes.
//
import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine
import FirebaseAuth

@MainActor
class CreateAdventureVM: ObservableObject {
    @Published var college: String = ""
    @Published var moods: Set<String> = []
    @Published var timeOfDay: String = "Any"
    @Published var extraDetail: String = ""
    @AppStorage("maxDistanceMiles") var maxDistanceMiles: Double = 1.0
    struct CollegeSuggestion: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let coordinate: CLLocationCoordinate2D

        static func == (lhs: CollegeSuggestion, rhs: CollegeSuggestion) -> Bool {
            lhs.name == rhs.name &&
            lhs.coordinate.latitude == rhs.coordinate.latitude &&
            lhs.coordinate.longitude == rhs.coordinate.longitude
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
        }
    }

    @Published var collegeSuggestions: [CollegeSuggestion] = []
    @Published var collegeLat: Double = 0
    @Published var collegeLng: Double = 0

    private var cancellables = Set<AnyCancellable>()
    private var shouldTriggerSearch = true

    init() {
        $college
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if self.shouldTriggerSearch {
                    self.fetchCollegeSuggestions(for: query)
                } else {
                    // skip once after programmatic selection
                    self.shouldTriggerSearch = true
                }
            }
            .store(in: &cancellables)
    }

    func selectCollege(_ suggestion: CollegeSuggestion) {
        college = suggestion.name
        collegeLat = suggestion.coordinate.latitude
        collegeLng = suggestion.coordinate.longitude
        collegeSuggestions = []
        shouldTriggerSearch = false
    }


    private func fetchCollegeSuggestions(for query: String) {
        guard !query.isEmpty else { collegeSuggestions = []; return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.university])
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self, let items = response?.mapItems else { return }
            let suggestions = items.compactMap { item -> CollegeSuggestion? in
                guard let name = item.name else { return nil }
                return CollegeSuggestion(name: name, coordinate: item.placemark.coordinate)
            }
            DispatchQueue.main.async {
                self.collegeSuggestions = Array(suggestions.prefix(6))
            }
        }
    }
    @Published var isLoading = false
    @Published var themes: [CampusTheme] = []
    // pagination fields (not used after rollback)
    @Published var nextCursor: String? = nil
    @Published var isLoadingMore: Bool = false
    @Published var error: String?

    // Firestore not used here

    private func ensureSignedIn() async throws {
        if Auth.auth().currentUser == nil {
            try await Auth.auth().signInAnonymously()
        }
    }

    func generateThemes() async {
        guard !college.isEmpty else { error = "Please enter a college"; return }
        if collegeLat == 0 || collegeLng == 0 {
            // Attempt forward geocoding if user typed college but didn't select suggestion
            do {
                let placemarks = try await CLGeocoder().geocodeAddressString(college)
                if let first = placemarks.first {
                    collegeLat = first.location?.coordinate.latitude ?? 0
                    collegeLng = first.location?.coordinate.longitude ?? 0
                }
            } catch {
                self.error = "Unable to determine location for \(college). Please pick from suggestions."
                return
            }
        }
        guard !college.isEmpty else { error = "Please enter a college"; return }
        isLoading = true
        do {
            try await ensureSignedIn()
        } catch {
            self.error = "Authentication failed: \(error.localizedDescription)"
            isLoading = false
            return
        }
        error = nil
        do {
            let meters = Int(maxDistanceMiles * 1609.34)
            themes = try await CampusPlanService.shared.generatePlans(college: college, latitude: collegeLat, longitude: collegeLng, mood: moods.joined(separator: ","), timeOfDay: timeOfDay, maxDistanceMeters: meters)
            if themes.isEmpty {
                error = "No themes found for your filters. Try changing mood or time."
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
