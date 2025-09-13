//
//  LocationSearchVM.swift
//  DateGenie
//
//  Created by AI on 7/17/25.
//  Wraps MKLocalSearchCompleter to provide location autocomplete suggestions.
//

import Foundation
import MapKit

@MainActor
final class LocationSearchVM: NSObject, ObservableObject {
    @Published var query: String = "" {
        didSet {
            completer.queryFragment = query
        }
    }
    @Published var suggestions: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = .address
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
    }
}

extension LocationSearchVM: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.suggestions = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }
}
