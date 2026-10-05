import SwiftUI
import UIKit

/// A photo picked for scanning, for presenting the review sheet.
struct ScannedReceipt: Identifiable {
    let id = UUID()
    let image: UIImage?
}

/// Reads a receipt photo and holds the purchases found, for the person to correct before applying.
@MainActor
final class ReceiptReviewModel: ObservableObject {
    enum Phase: Equatable {
        case reading, ready, empty, failed
    }

    enum Action: Hashable {
        case checkOff, add, skip
    }

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var name: String
        let price: Decimal?
        let quantity: Int
        /// The open list item this purchase is, if any.
        let match: GroceryItem?
        /// A list item already checked off that this purchase is, e.g. on a second scan.
        var alreadyBought: GroceryItem? = nil
        var action: Action
    }

    @Published private(set) var phase: Phase = .reading
    @Published var rows: [Row] = []
    private let recognizer: TextRecognizer

    init(recognizer: TextRecognizer = VisionTextRecognizer()) {
        self.recognizer = recognizer
    }

    /// Each list item can be claimed by one receipt line only, the first in receipt order. A line
    /// matching something already checked off (e.g. the same receipt scanned again) is skipped by
    /// default; a loose match is offered but defaults to adding.
    func read(_ image: UIImage?, listItems: [GroceryItem]) async {
        phase = .reading
        rows = []
        guard let image, let cgImage = image.cgImage else {
            phase = .failed
            return
        }
        let fragments: [TextFragment]
        do {
            fragments = try await recognizer.recognize(cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        } catch {
            phase = .failed
            return
        }
        var unclaimed = listItems.filter { !$0.isCompleted }
        let bought = listItems.filter(\.isCompleted)
        rows = ReceiptParser.parse(lines: ReceiptText.lines(from: fragments)).map { item in
            if let match = ReceiptMatcher.match(item, in: unclaimed) {
                unclaimed.removeAll { $0.id == match.id }
                let action: Action = ReceiptMatcher.isClose(item, to: match) ? .checkOff : .add
                return Row(name: item.name, price: item.price, quantity: item.quantity, match: match, action: action)
            }
            if let done = ReceiptMatcher.match(item, in: bought), ReceiptMatcher.isClose(item, to: done) {
                return Row(name: item.name, price: item.price, quantity: item.quantity, match: nil, alreadyBought: done, action: .skip)
            }
            return Row(name: item.name, price: item.price, quantity: item.quantity, match: nil, action: .add)
        }
        phase = rows.isEmpty ? .empty : .ready
    }

    var decisions: [ReceiptDecision] {
        rows.map { row in
            switch row.action {
            case .checkOff:
                if let match = row.match { return .checkOff(itemId: match.id) }
                return .addBought(name: row.name)
            case .add:
                return .addBought(name: row.name)
            case .skip:
                return .skip
            }
        }
    }
}

/// The purchases read from a receipt, each with what to do about it.
struct ReceiptReviewView: View {
    let receipt: ScannedReceipt
    let listItems: [GroceryItem]
    let onApply: ([ReceiptDecision]) -> Void
    @StateObject private var model = ReceiptReviewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Review Receipt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if model.phase == .ready {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Apply") {
                                onApply(model.decisions)
                                dismiss()
                            }
                        }
                    }
                }
        }
        .task { await model.read(receipt.image, listItems: listItems) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .reading:
            ProgressView("Reading receipt…")
        case .empty:
            unavailable("No items found", "Try a flatter, well-lit photo of the whole receipt.")
        case .failed:
            unavailable("Couldn't read that photo", "Try taking or choosing another photo.")
        case .ready:
            Form {
                Section {
                    ForEach($model.rows) { $row in
                        ReceiptRowEditor(row: $row)
                    }
                } footer: {
                    Text("Read on this iPhone; the photo isn't saved. Purchases are added as bought by you.")
                }
            }
        }
    }

    private func unavailable(_ title: String, _ message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "doc.text.magnifyingglass")
        } description: {
            Text(message)
        } actions: {
            Button("Try Another Photo") { dismiss() }
        }
    }
}

private struct ReceiptRowEditor: View {
    @Binding var row: ReceiptReviewModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Item", text: $row.name)
                if let price = row.price {
                    Text(price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Picker("Action", selection: $row.action) {
                if let match = row.match {
                    Text("Check off “\(match.title)”").tag(ReceiptReviewModel.Action.checkOff)
                }
                Text(row.quantity > 1 ? "Add as bought (×\(row.quantity))" : "Add as bought").tag(ReceiptReviewModel.Action.add)
                Text(row.alreadyBought.map { "Skip (“\($0.title)” already bought)" } ?? "Skip").tag(ReceiptReviewModel.Action.skip)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

/// The system camera, for photographing a receipt.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }
    }
}
