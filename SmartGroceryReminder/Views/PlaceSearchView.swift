import SwiftUI
import MapKit

/// Searches Apple Maps for a grocery store or a home address and hands back the chosen place.
struct PlaceSearchView: View {
    let kind: GeoPlace.PlaceKind
    let near: CLLocationCoordinate2D?
    let onPick: (GeoPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlaceSearchResult] = []
    @State private var status: String?

    var body: some View {
        NavigationStack {
            List(results) { result in
                Button {
                    onPick(result.geoPlace(kind: kind))
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if !result.address.isEmpty {
                            Text(result.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityHint(kind == .home ? "Sets this address as home" : "Adds this store")
            }
            .overlay {
                if results.isEmpty, let status {
                    ContentUnavailableView(status, systemImage: "magnifyingglass")
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: kind == .home ? "Street address" : "Store name, e.g. Safeway"
            )
            .task(id: query) { await search() }
            .navigationTitle(kind == .home ? "Find Home" : "Find a Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            status = nil
            return
        }
        // .task(id:) restarts on every keystroke, so this pause debounces typing.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        status = "Searching…"
        do {
            let found = try await PlaceSearchService.search(text, kind: kind, near: near)
            guard !Task.isCancelled else { return }
            results = found
            status = found.isEmpty ? "No matches" : nil
        } catch let error as MKError where error.code == .placemarkNotFound {
            results = []
            status = "No matches"
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            status = "Search failed. Check your connection and try again."
        }
    }
}
