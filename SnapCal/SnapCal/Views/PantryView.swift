import SwiftUI

// Pantry — what you have on hand. Add items manually (barcode scan
// comes next). Categorized sections; tap a row to edit; long-press for
// quick delete. Feeds Cook once recipe suggestions ship.
struct PantryView: View {
    @State private var store = PantryStore.shared
    @State private var showingAdd = false
    @State private var editing: PantryItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if store.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.grouped(), id: \.category) { group in
                            section(for: group.category, items: group.items)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .tabBarFadesOnScroll()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                            .foregroundStyle(SCTheme.Colors.accentPink)
                    }
                    .accessibilityLabel("Add pantry item")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddPantryItemSheet()
            }
            .sheet(item: $editing) { item in
                AddPantryItemSheet(editing: item)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(text: "Pantry", tint: SCTheme.Colors.carbGreen)
            Text("What's on hand")
                .font(SCTheme.Type_.title(30))
                .foregroundStyle(.primary)
            Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s") stocked. Tap + to add, tap a row to edit, hold to delete.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SCTheme.Colors.carbGreen.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "cabinet.fill")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(SCTheme.Colors.carbGreen)
            }
            Text("No items yet")
                .font(SCTheme.Type_.cardTitle())
                .foregroundStyle(.primary)
            Text("Add what you have and Cook will suggest recipes that fit your day's macros.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            Button {
                showingAdd = true
            } label: {
                Label("Add your first item", systemImage: "plus")
                    .font(SCTheme.Type_.button())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(SCTheme.Gradients.cta, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .scCardStyle()
    }

    // MARK: Section per category

    private func section(for category: PantryCategory, items: [PantryItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(SCTheme.Colors.accentPink)
                Text(category.label.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        editing = item
                    } label: {
                        PantryRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editing = item
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.delete(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct PantryRow: View {
    let item: PantryItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(quantityLabel)
                        .font(SCTheme.Type_.caption())
                        .foregroundStyle(.secondary)
                    if case let status = item.expirationStatus, status != .none {
                        expirationChip(for: status)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: item.category.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .scCardStyle()
    }

    private var quantityLabel: String {
        let qty = formatted(item.quantity)
        return item.unit == .count ? "\(qty) \(item.unit.label)" : "\(qty) \(item.unit.label)"
    }

    @ViewBuilder
    private func expirationChip(for status: ExpirationStatus) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .ok(let days):
            chip(text: "\(days)d left", tint: .secondary)
        case .soon(let days):
            let text = days == 0 ? "Expires today" : "\(days)d left"
            chip(text: text, tint: SCTheme.Colors.accentOrange)
        case .expired:
            chip(text: "Expired", tint: SCTheme.Colors.accentPink)
        }
    }

    private func chip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

private func formatted(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        return String(Int(value))
    }
    return String(format: "%g", value)
}

#Preview {
    PantryView()
}
