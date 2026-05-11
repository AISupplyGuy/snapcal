import SwiftUI

// Manual add / edit for a single pantry item. Dark-glass aesthetic
// matching LogWeight / Paywall — kicker pill, glass cards, custom
// toggle, gradient CTA. Pass an existing item to edit.
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
        ZStack(alignment: .top) {
            ambient
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    nameAndCategoryCard
                    quantityCard
                    expirationCard
                    notesCard
                    if editing != nil { deleteButton }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            closeButton
        }
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    // MARK: Ambient

    private var ambient: some View {
        ZStack {
            RadialGradient(
                colors: [SCTheme.Colors.carbGreen.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 360
            )
            RadialGradient(
                colors: [SCTheme.Colors.accentOrange.opacity(0.14), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var closeButton: some View {
        HStack {
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(
                text: editing == nil ? "Add to pantry" : "Edit item",
                tint: SCTheme.Colors.carbGreen
            )
            Text(editing == nil ? "What's coming home?" : (name.isEmpty ? "Edit item" : name))
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

    // MARK: Name + category (combined)

    private var nameAndCategoryCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Name")
                    TextField("e.g. Organic Bananas", text: $name)
                        .textInputAutocapitalization(.words)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .submitLabel(.done)
                }
                Divider().background(.white.opacity(0.06))
                VStack(alignment: .leading, spacing: 10) {
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
            .foregroundStyle(active ? .white : .primary.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if active {
                    Capsule().fill(SCTheme.Gradients.cta)
                        .shadow(color: SCTheme.Colors.accentPink.opacity(0.32), radius: 8, y: 4)
                } else {
                    Capsule().fill(.white.opacity(0.06))
                }
            }
            .overlay {
                if !active {
                    Capsule().strokeBorder(.white.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Quantity

    private var quantityCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                fieldLabel("Quantity")
                HStack(spacing: 12) {
                    stepper("minus") {
                        if let q = parsedQuantity, q > 0.25 {
                            quantityString = Self.formatted(max(0.25, q - 0.25))
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("1", text: $quantityString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
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
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .heavy))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.08)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.white.opacity(0.04)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.06)))

                    stepper("plus") {
                        if let q = parsedQuantity {
                            quantityString = Self.formatted(q + 0.25)
                        } else {
                            quantityString = "1"
                        }
                    }
                }
            }
        }
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(SCTheme.Gradients.cta, in: Circle())
                .shadow(color: SCTheme.Colors.accentPink.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: Expiration

    private var expirationCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill((hasExpiration ? SCTheme.Colors.accentOrange : Color.white).opacity(hasExpiration ? 0.18 : 0.06))
                            .frame(width: 36, height: 36)
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(hasExpiration ? SCTheme.Colors.accentOrange : .secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track expiration")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Soft nudge before it goes off.")
                            .font(SCTheme.Type_.caption())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    pillToggle(isOn: $hasExpiration)
                }
                if hasExpiration {
                    DatePicker(
                        "Expires",
                        selection: $expirationDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .tint(SCTheme.Colors.accentOrange)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func pillToggle(isOn: Binding<Bool>) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(duration: 0.25)) { isOn.wrappedValue.toggle() }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(isOn.wrappedValue
                          ? AnyShapeStyle(SCTheme.Gradients.cta)
                          : AnyShapeStyle(Color.white.opacity(0.1)))
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .padding(.horizontal, 3)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Notes

    private var notesCard: some View {
        glassCard {
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

    private var deleteButton: some View {
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
            .background(Capsule().fill(SCTheme.Colors.accentPink.opacity(0.12)))
            .overlay(Capsule().strokeBorder(SCTheme.Colors.accentPink.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Save bar

    private var saveBar: some View {
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
            .shadow(color: SCTheme.Colors.accentPink.opacity(canSave ? 0.32 : 0), radius: 12, y: 6)
            .opacity(canSave ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: Helpers

    private func glassCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SCTheme.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SCTheme.Radius.lg, style: .continuous)
                .strokeBorder(.white.opacity(0.07))
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.2)
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
