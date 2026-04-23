import SwiftUI

// Manual add / edit for a single pantry item. Reused for both flows —
// pass an existing item to edit it. Barcode scan will front this sheet
// later with pre-filled fields from the Open Food Facts lookup.
struct AddPantryItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var quantityString: String
    @State private var unit: PantryUnit
    @State private var category: PantryCategory
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date
    @State private var note: String

    private let editing: PantryItem?

    init(editing: PantryItem? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _quantityString = State(initialValue: editing.map { formatted($0.quantity) } ?? "1")
        _unit = State(initialValue: editing?.unit ?? .count)
        _category = State(initialValue: editing?.category ?? .other)
        _hasExpiration = State(initialValue: editing?.expirationDate != nil)
        _expirationDate = State(
            initialValue: editing?.expirationDate
                ?? Calendar.current.date(byAdding: .day, value: 7, to: .now)!
        )
        _note = State(initialValue: editing?.note ?? "")
    }

    private var parsedQuantity: Double? {
        Double(quantityString.trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (parsedQuantity ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Category", selection: $category) {
                        ForEach(PantryCategory.allCases) { cat in
                            Label(cat.label, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                }

                Section("Quantity") {
                    HStack {
                        TextField("1", text: $quantityString)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(PantryUnit.allCases) { u in
                                Text(u.label).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 100)
                    }
                }

                Section("Expiration") {
                    Toggle("Track expiration", isOn: $hasExpiration.animation())
                    if hasExpiration {
                        DatePicker("Expires", selection: $expirationDate, displayedComponents: [.date])
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            if let editing {
                                PantryStore.shared.delete(editing)
                            }
                            dismiss()
                        } label: {
                            Label("Delete item", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add to pantry" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let quantity = parsedQuantity, canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = PantryItem(
            id: editing?.id ?? UUID(),
            name: trimmedName,
            quantity: quantity,
            unit: unit,
            category: category,
            expirationDate: hasExpiration ? expirationDate : nil,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            addedAt: editing?.addedAt ?? .now,
            updatedAt: .now
        )
        if editing == nil {
            PantryStore.shared.add(item)
        } else {
            PantryStore.shared.update(item)
        }
        dismiss()
    }
}

private func formatted(_ value: Double) -> String {
    // Strip trailing zeros so "1.0" shows as "1" in the editor.
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        return String(Int(value))
    }
    return String(format: "%g", value)
}
