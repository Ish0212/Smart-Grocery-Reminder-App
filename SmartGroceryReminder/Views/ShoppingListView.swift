import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingAdd = false
    @State private var newTitle = ""
    @State private var newAisle = ""
    @State private var newNotes = ""

    private var openItems: [GroceryItem] {
        appState.shoppingList.filter { !$0.isCompleted }
    }

    private var doneItems: [GroceryItem] {
        appState.shoppingList.filter(\.isCompleted)
    }

    var body: some View {
        NavigationStack {
            List {
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
                NavigationStack {
                    Form {
                        TextField("Item name", text: $newTitle)
                        TextField("Aisle (optional)", text: $newAisle)
                        TextField("Notes (optional)", text: $newNotes, axis: .vertical)
                            .lineLimit(3...5)
                    }
                    .navigationTitle("New Item")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                Task {
                                    await appState.addItem(newTitle.trimmingCharacters(in: .whitespaces), notes: newNotes, aisle: newAisle)
                                    newTitle = ""
                                    newAisle = ""
                                    newNotes = ""
                                    showingAdd = false
                                }
                            }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
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
        .accessibilityHint("Double tap to toggle completion")
    }
}

#Preview {
    ShoppingListView()
        .environmentObject(AppState())
}
