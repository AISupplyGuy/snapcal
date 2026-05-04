import SwiftUI

// Manual add / edit for a single pantry item, styled to match the rest
// of SnapCal — kicker pill, card surfaces, gradient CTA, rounded type.
// Pass an existing item to edit; otherwise this is the add flow.
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
        _quantityString = State(initialValue: editing.map { Self.formatted($0.quantity) } ?? "1")
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    nameCard
                    categoryCard
                    quantityCard
                    expirationCard
                    notesCard
                    if editing != nil { deleteCard }
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SCTheme.Colors.accentPink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(
                text: editing == nil ? "Add to pantry" : "Edit item",
                tint: SCTheme.Colors.carbGreen
            )
            Text(editing == nil ? "What's coming home?" : name)
                .font(SCTheme.Type_.title(28))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(editing == nil
                ? "Stock it once and SnapCal tracks freshness for you."
                : "Update anything that's changed.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: Name

    private var nameCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Name")
                TextField("e.g. Organic Bananas", text: $name)
                    .textInputAutocapitalization(.words)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .submitLabel(.done)
            }
        }
    }

    // MARK: Category

    private var categoryCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Category")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PantryCategory.allCases) { cat in
                            categoryChip(cat)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func categoryChip(_ cat: PantryCategory) -> some View {
        let active = (cat == category)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            category = cat
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.systemImage)
                    .font(.system(size: 12, weight: .heavy))
                Text(cat.label)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(active ? .white : SCTheme.Colors.accentPink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Group {
                    if active {
                        Capsule().fill(SCTheme.Gradients.cta)
                    } else {
                        Capsule().fill(SCTheme.Colors.accentPink.opacity(0.12))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Quantity

    private var quantityCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Quantity")
                HStack(spacing: 12) {
                    Button {
                        if let q = parsedQuantity, q > 0.25 {
                            quantityString = Self.formatted(max(0.25, q - 0.25))
                        }
                    } label: {
                        stepperGlyph("minus")
                    }
                    .buttonStyle(.plain)

                    TextField("1", text: $quantityString)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SCTheme.Colors.accentPink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    Button {
                        if let q = parsedQuantity {
                            quantityString = Self.formatted(q + 0.25)
                        } else {
                            quantityString = "1"
                        }
                    } label: {
                        stepperGlyph("plus")
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Picker("Unit", selection: $unit) {
                            ForEach(PantryUnit.allCases) { u in
                                Text(u.label).tag(u)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(unit.label)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(SCTheme.Colors.accentPink.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    private func stepperGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(SCTheme.Gradients.cta, in: Circle())
    }

    // MARK: Expiration

    private var expirationCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $hasExpiration.animation()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track expiration")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Get a soft nudge before it goes off.")
                            .font(SCTheme.Type_.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(SCTheme.Colors.accentPink)

                if hasExpiration {
                    DatePicker(
                        "Expires",
                        selection: $expirationDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .tint(SCTheme.Colors.accentPink)
                }
            }
        }
    }

    // MARK: Notes

    private var notesCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Notes")
                TextField("Optional — brand, store, anything", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: Delete

    private var deleteCard: some View {
        Button(role: .destructive) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let editing {
                PantryStore.shared.delete(editing)
            }
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                Text("Delete item")
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(SCTheme.Colors.accentPink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(SCTheme.Colors.accentPink.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Save bar

    private var saveBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                save()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: editing == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                    Text(editing == nil ? "Add to pantry" : "Save changes")
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(SCTheme.Gradients.cta, in: Capsule())
                .opacity(canSave ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: Helpers

    private func cardShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(.secondary)
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

    private static func formatted(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}
