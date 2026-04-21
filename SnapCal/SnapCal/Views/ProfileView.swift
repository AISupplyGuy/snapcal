import SwiftUI

// User preferences hub. Today: daily nutrition goals that drive the Today
// rings. More panels can live here later (units, reminders, privacy, etc.).
struct ProfileView: View {
    @State private var goals = GoalsStore.shared.goals
    @State private var showingResetConfirm = false
    @State private var savedFlash = false

    private let store = GoalsStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    goalCard(
                        label: "Calories",
                        unit: "kcal",
                        tint: SCTheme.Colors.accentPink,
                        softBg: SCTheme.Colors.caloriesSoft,
                        value: $goals.calories,
                        range: 800...6000,
                        step: 50
                    )

                    goalCard(
                        label: "Protein",
                        unit: "g",
                        tint: SCTheme.Colors.proteinBlue,
                        softBg: SCTheme.Colors.proteinSoft,
                        value: $goals.proteinGrams,
                        range: 20...400,
                        step: 5
                    )

                    goalCard(
                        label: "Carbs",
                        unit: "g",
                        tint: SCTheme.Colors.carbGreen,
                        softBg: SCTheme.Colors.carbSoft,
                        value: $goals.carbGrams,
                        range: 20...800,
                        step: 5
                    )

                    goalCard(
                        label: "Fat",
                        unit: "g",
                        tint: SCTheme.Colors.accentOrange,
                        softBg: SCTheme.Colors.caloriesSoft,
                        value: $goals.fatGrams,
                        range: 10...300,
                        step: 5
                    )

                    goalCard(
                        label: "Fiber",
                        unit: "g",
                        tint: SCTheme.Colors.standTeal,
                        softBg: SCTheme.Colors.carbSoft,
                        value: $goals.fiberGrams,
                        range: 5...100,
                        step: 1
                    )

                    actions
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Reset goals to defaults?",
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    store.resetToDefaults()
                    goals = store.goals
                    flashSaved()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This restores calorie, protein, carb, fat, and fiber targets to SnapCal's starting values.")
            }
        }
        // Any edit flows through a single save — persist on disappear so
        // quick tweaks don't need a manual Save tap.
        .onChange(of: goals) { _, next in
            store.update(next)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(text: "Daily goals", tint: SCTheme.Colors.accentOrange)
            Text("Set your targets")
                .font(SCTheme.Type_.title(30))
                .foregroundStyle(.primary)
            Text("Rings on Today fill against these numbers. Slide to adjust — changes save automatically.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if savedFlash {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SCTheme.Colors.carbGreen)
                    Text("Saved")
                        .font(SCTheme.Type_.caption())
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Goal card

    private func goalCard(
        label: String,
        unit: String,
        tint: Color,
        softBg: Color,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(SCTheme.Type_.cardTitle())
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(Int(value.wrappedValue))")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(tint)
                        .contentTransition(.numericText(value: value.wrappedValue))
                        .animation(.easeOut(duration: 0.15), value: value.wrappedValue)
                    Text(unit)
                        .font(SCTheme.Type_.caption())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(softBg, in: Capsule())
            }

            Slider(value: value, in: range, step: step) {
                Text(label)
            } minimumValueLabel: {
                Text("\(Int(range.lowerBound))")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("\(Int(range.upperBound))")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            }
            .tint(tint)

            HStack(spacing: 10) {
                stepperButton(symbol: "minus", tint: tint) {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                }
                Spacer()
                stepperButton(symbol: "plus", tint: tint) {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                }
            }
        }
        .padding(18)
        .scCardStyle()
    }

    private func stepperButton(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                showingResetConfirm = true
            } label: {
                Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    .font(SCTheme.Type_.button())
                    .foregroundStyle(SCTheme.Colors.accentPink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: SCTheme.Radius.md)
                            .stroke(SCTheme.Colors.accentPink.opacity(0.35), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func flashSaved() {
        withAnimation(.easeIn(duration: 0.15)) { savedFlash = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { savedFlash = false }
            }
        }
    }
}

#Preview {
    ProfileView()
}
