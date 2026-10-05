import SwiftUI
import PhotosUI

struct ShoppingListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingAdd = false
    @State private var newTitle = ""
    @State private var newAisle = ""
    @State private var newNotes = ""
    @State private var editing: GroceryItem?
    @State private var showingCamera = false
    /// Held until the camera has closed: presenting the review sheet while it's still closing can fail.
    @State private var cameraPhoto: UIImage?
    @State private var showingPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var scannedReceipt: ScannedReceipt?
    @State private var receiptResult: ReceiptResult?

    private var openItems: [GroceryItem] {
        appState.shoppingList.filter { !$0.isCompleted }
    }

    private var doneItems: [GroceryItem] {
        appState.shoppingList.filter(\.isCompleted)
    }

    var body: some View {
        NavigationStack {
            List {
                if let syncError = appState.syncErrorMessage {
                    Label(syncError, systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if appState.hasUnsyncedChanges {
                    Label("Saved on this iPhone. It will sync when you're back online.", systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if openItems.isEmpty && doneItems.isEmpty {
                    ContentUnavailableView(
                        "List is empty",
                        systemImage: "cart",
                        description: Text("Add items you need to pick up. Store and home reminders use this list.")
                    )
                    .listRowBackground(Color.clear)
                }

                if !openItems.isEmpty {
                    Section("To buy (\(openItems.count))") {
                        ForEach(openItems) { item in
                            GroceryRow(item: item) {
                                Task { await appState.toggleItem(item) }
                            }
                            .modifier(EditActions(item: item, editing: $editing))
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { openItems[$0].id }
                            let global = IndexSet(appState.shoppingList.indices.filter { ids.contains(appState.shoppingList[$0].id) })
                            Task { await appState.deleteItems(at: global) }
                        }
                    }
                }

                if !doneItems.isEmpty {
                    Section("Completed") {
                        ForEach(doneItems) { item in
                            GroceryRow(item: item) {
                                Task { await appState.toggleItem(item) }
                            }
                            .modifier(EditActions(item: item, editing: $editing))
                            .opacity(0.55)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { doneItems[$0].id }
                            let global = IndexSet(appState.shoppingList.indices.filter { ids.contains(appState.shoppingList[$0].id) })
                            Task { await appState.deleteItems(at: global) }
                        }
                    }
                }
            }
            .navigationTitle("Grocery List")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if CameraPicker.isAvailable {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                            }
                        }
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label("Choose Photo", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                    .accessibilityLabel("Scan Receipt")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add grocery item")
                }
            }
            .sheet(isPresented: $showingAdd) {
                ItemForm(
                    navigationTitle: "New Item",
                    confirmTitle: "Add",
                    title: $newTitle,
                    aisle: $newAisle,
                    notes: $newNotes,
                    onCancel: { showingAdd = false },
                    onConfirm: {
                        Task {
                            await appState.addItem(newTitle.trimmingCharacters(in: .whitespaces), notes: newNotes, aisle: newAisle)
                            newTitle = ""
                            newAisle = ""
                            newNotes = ""
                            showingAdd = false
                        }
                    }
                )
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedPhoto, matching: .images)
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                pickedPhoto = nil
                Task {
                    // A photo that can't be loaded or decoded shows the review sheet's "couldn't read" state.
                    let data = try? await item.loadTransferable(type: Data.self)
                    scannedReceipt = ScannedReceipt(image: data.flatMap(UIImage.init(data:)))
                }
            }
            .fullScreenCover(isPresented: $showingCamera, onDismiss: {
                if let photo = cameraPhoto {
                    cameraPhoto = nil
                    scannedReceipt = ScannedReceipt(image: photo)
                }
            }) {
                CameraPicker { image in
                    cameraPhoto = image
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
            .sheet(item: $scannedReceipt) { receipt in
                ReceiptReviewView(receipt: receipt, listItems: appState.shoppingList) { decisions in
                    Task { receiptResult = await appState.applyReceipt(decisions) }
                }
            }
            .alert(
                "Receipt applied",
                isPresented: Binding(get: { receiptResult != nil }, set: { if !$0 { receiptResult = nil } }),
                presenting: receiptResult
            ) { _ in
                Button("OK") {}
            } message: { result in
                Text("Checked off \(result.checkedOff), added \(result.added) as bought.")
            }
            .sheet(item: $editing) { item in
                ItemEditor(item: item) { title, notes, aisle in
                    Task { await appState.editItem(item, title: title, notes: notes, aisle: aisle) }
                }
            }
        }
    }
}

/// Swipe right, or long-press, to edit an item.
private struct EditActions: ViewModifier {
    let item: GroceryItem
    @Binding var editing: GroceryItem?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                Button("Edit") { editing = item }
                    .tint(.blue)
            }
            .contextMenu {
                Button {
                    editing = item
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
    }
}

/// The fields of an item, for adding one and for editing one.
struct ItemForm: View {
    let navigationTitle: String
    let confirmTitle: String
    @Binding var title: String
    @Binding var aisle: String
    @Binding var notes: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $title)
                TextField("Aisle (optional)", text: $aisle)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...5)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: onConfirm)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Edits a copy of the item; Save hands back the new name, aisle and notes.
private struct ItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var aisle: String
    @State private var notes: String
    let onSave: (_ title: String, _ notes: String, _ aisle: String) -> Void

    init(item: GroceryItem, onSave: @escaping (_ title: String, _ notes: String, _ aisle: String) -> Void) {
        _title = State(initialValue: item.title)
        _aisle = State(initialValue: item.aisle)
        _notes = State(initialValue: item.notes)
        self.onSave = onSave
    }

    var body: some View {
        ItemForm(
            navigationTitle: "Edit Item",
            confirmTitle: "Save",
            title: $title,
            aisle: $aisle,
            notes: $notes,
            onCancel: { dismiss() },
            onConfirm: {
                onSave(title, notes, aisle)
                dismiss()
            }
        )
    }
}

struct GroceryRow: View {
    let item: GroceryItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? Color("AccentGreen") : .secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(.primary)
                    if !item.aisle.isEmpty || !item.notes.isEmpty {
                        Text([item.aisle, item.notes].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title)\(item.isCompleted ? ", completed" : ", not completed")")
        .accessibilityHint("Double tap to toggle completion. Swipe right to edit.")
    }
}

#Preview {
    ShoppingListView()
        .environmentObject(AppState())
}
