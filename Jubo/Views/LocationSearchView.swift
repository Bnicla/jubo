import SwiftUI
import MapKit

/// Location search view with autocomplete using MapKit
struct LocationSearchView: View {
    @Binding var selectedLocation: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchCompleter = LocationSearchCompleter()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty && !selectedLocation.isEmpty {
                    Section("Current Location") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(selectedLocation)
                        }
                    }
                }

                Section {
                    TextField("Search city or region...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) { _, newValue in
                            searchCompleter.search(query: newValue)
                        }
                }

                if !searchCompleter.results.isEmpty {
                    Section("Suggestions") {
                        ForEach(searchCompleter.results, id: \.self) { result in
                            Button {
                                selectLocation(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .foregroundColor(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !selectedLocation.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            selectedLocation = ""
                            dismiss()
                        } label: {
                            Label("Clear Location", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("Set Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func selectLocation(_ result: MKLocalSearchCompletion) {
        // Format as "City, State" or "City, Country"
        if result.subtitle.isEmpty {
            selectedLocation = result.title
        } else {
            selectedLocation = "\(result.title), \(result.subtitle)"
        }
        dismiss()
    }
}

// MARK: - Location Search Completer

@MainActor
class LocationSearchCompleter: NSObject, ObservableObject {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        completer.queryFragment = query
    }
}

extension LocationSearchCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            // Filter to cities/regions, limit results
            self.results = Array(completer.results.prefix(8))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
    }
}

#Preview {
    LocationSearchView(selectedLocation: .constant("Austin, TX"))
}
