import SwiftUI

// Pantry — what you have on hand. Add items manually (barcode scan
// comes next). Categorized sections; tap a row to edit; long-press for
// quick delete. Feeds Cook once recipe suggestions ship.
struct PantryView: View {
    @State private var store = PantryStore.shared
    @State private var showingAdd = false
    @State private var showingReceiptScan = false
    @State private var editing: PantryItem?
    @State private var notificationRouter = NotificationRouter.shared
    // Synced from notificationRouter.scanReceiptRequestVersion on first
    // appear; reading the @MainActor property in a State default
    // expression would be an isolation error.
    @State private var lastSeenScanRequest = 0
    // Bulk-select mode: tap rows to toggle, then "Delete N" floats up
    // from the bottom. Tapping while NOT selecting opens the edit sheet.
    @State private var selecting = false
    @State private var selected: Set<UUID> = []

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

                    comingSoonBlock
                        .padding(.top, 8)
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
                    HStack(spacing: 14) {
                        if !store.items.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selecting.toggle()
                                    if !selecting { selected.removeAll() }
                                }
                            } label: {
                                Text(selecting ? "Done" : "Select")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(SCTheme.Colors.accentPink)
                            }
                        }
                        if !selecting {
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
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting { selectionBar }
            }
            .sheet(isPresented: $showingAdd) {
                AddPantryItemSheet()
            }
            .sheet(item: $editing) { item in
                AddPantryItemSheet(editing: item)
            }
            .fullScreenCover(isPresented: $showingReceiptScan) {
                ReceiptScanFlowView(onClose: { showingReceiptScan = false })
            }
            .onChange(of: notificationRouter.scanReceiptRequestVersion) { _, new in
                guard new != lastSeenScanRequest else { return }
                lastSeenScanRequest = new
                showingReceiptScan = true
            }
            .onAppear {
                // Catches the case where the user tapped the grocery
                // notification while another tab was active — the version
                // bump happened before this view existed so onChange
                // didn't see it.
                if notificationRouter.scanReceiptRequestVersion != lastSeenScanRequest {
                    lastSeenScanRequest = notificationRouter.scanReceiptRequestVersion
                    showingReceiptScan = true
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(text: "Pantry", tint: SCTheme.Colors.carbGreen)
            HStack(alignment: .firstTextBaseline) {
                Text("What's on hand")
                    .font(SCTheme.Type_.title(30))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    showingReceiptScan = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 15, weight: .heavy))
                        Text("Scan receipt")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(SCTheme.Gradients.cta, in: Capsule())
                    .shadow(color: SCTheme.Colors.accentPink.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan receipt")
            }
            Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s") stocked. Scan a receipt to add many at once, or tap + for manual.")
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
                        if selecting {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if selected.contains(item.id) {
                                selected.remove(item.id)
                            } else {
                                selected.insert(item.id)
                            }
                        } else {
                            editing = item
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if selecting {
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundStyle(
                                        selected.contains(item.id)
                                            ? SCTheme.Colors.accentPink
                                            : .secondary.opacity(0.5)
                                    )
                                    .transition(.scale.combined(with: .opacity))
                            }
                            PantryRow(item: item)
                        }
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

    // MARK: Selection bar

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button {
                if selected.count == store.items.count {
                    selected.removeAll()
                } else {
                    selected = Set(store.items.map(\.id))
                }
            } label: {
                Text(selected.count == store.items.count && !store.items.isEmpty ? "Clear" : "Select all")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(SCTheme.Colors.accentPink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(SCTheme.Colors.accentPink.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                guard !selected.isEmpty else { return }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                let toDelete = store.items.filter { selected.contains($0.id) }
                for item in toDelete { store.delete(item) }
                selected.removeAll()
                withAnimation(.easeInOut(duration: 0.2)) { selecting = false }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                    Text(selected.isEmpty ? "Delete" : "Delete \(selected.count)")
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(SCTheme.Gradients.cta, in: Capsule())
                .opacity(selected.isEmpty ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: Coming soon

    private var comingSoonBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMING SOON")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ComingSoonCard(
                icon: "calendar.badge.clock",
                title: "Expiration nudges",
                copy: "Soft reminders before ingredients go off, so Cook suggests recipes using what's running out first."
            )
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
