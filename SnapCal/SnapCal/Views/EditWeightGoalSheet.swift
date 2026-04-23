import SwiftUI

struct EditWeightGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProfilePrefsKeys.weightUnit) private var unitRaw = WeightUnit.pounds.rawValue

    @State private var direction: WeightGoal.Direction
    @State private var targetString: String
    @State private var weeklyRateString: String

    private let existing: WeightGoal?
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .pounds }
    private var currentKg: Double? {
        WeightLog.shared.latest?.kilograms
    }

    init(existing: WeightGoal? = nil) {
        self.existing = existing
        _direction = State(initialValue: existing?.direction ?? .lose)

        // Seed the fields in the user's preferred unit. Start with blanks
        // if no goal yet so the keyboard shows up clean.
        let u = WeightUnit(rawValue: UserDefaults.standard.string(forKey: ProfilePrefsKeys.weightUnit) ?? "") ?? .pounds
        if let existing {
            let targetDisplay = u == .kilograms
                ? existing.targetKilograms
                : existing.targetKilograms * 2.20462
            let rateDisplay = u == .kilograms
                ? existing.weeklyRateKilograms
                : existing.weeklyRateKilograms * 2.20462
            _targetString = State(initialValue: String(format: "%.1f", targetDisplay))
            _weeklyRateString = State(initialValue: String(format: "%.1f", rateDisplay))
        } else {
            _targetString = State(initialValue: "")
            _weeklyRateString = State(initialValue: "1.0")
        }
    }

    private var parsedTarget: Double? {
        Double(targetString.trimmingCharacters(in: .whitespaces))
    }
    private var parsedRate: Double? {
        Double(weeklyRateString.trimmingCharacters(in: .whitespaces))
    }
    private var canSave: Bool {
        currentKg != nil && (parsedTarget ?? 0) > 0 && (parsedRate ?? 0) >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Direction", selection: $direction) {
                        ForEach(WeightGoal.Direction.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(directionFooter)
                }

                if direction != .maintain {
                    Section("Target") {
                        HStack {
                            TextField("Target \(unit.label)", text: $targetString)
                                .keyboardType(.decimalPad)
                            Text(unit.label)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        HStack {
                            TextField("Weekly rate", text: $weeklyRateString)
                                .keyboardType(.decimalPad)
                            Text("\(unit.label)/week")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Pace")
                    } footer: {
                        Text("A safe rate for most people is 0.5–1.0 \(unit.label)/week in either direction.")
                    }
                } else {
                    Section {
                        HStack {
                            TextField("Maintain at", text: $targetString)
                                .keyboardType(.decimalPad)
                            Text(unit.label)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Target")
                    } footer: {
                        Text("We'll flag the goal as hit when you're within 2 \(unit.label) of target.")
                    }
                }

                if currentKg == nil {
                    Section {
                        Text("Log a current weight on Track before setting a goal.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            WeightGoalStore.shared.clear()
                            dismiss()
                        } label: {
                            Label("Remove goal", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Set weight goal" : "Edit weight goal")
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

    private var directionFooter: String {
        switch direction {
        case .lose:     return "Pick a lower target and a weekly pace. We'll track progress against today's starting weight."
        case .gain:     return "Pick a higher target and a weekly pace. We'll track progress against today's starting weight."
        case .maintain: return "Pick the weight you want to hold. A ±2 \(unit.label) band counts as on-target."
        }
    }

    private func save() {
        guard let target = parsedTarget, let startingKg = currentKg else { return }
        let rate = parsedRate ?? 0
        let targetKg = unit == .kilograms ? target : target / 2.20462
        let rateKg = unit == .kilograms ? rate : rate / 2.20462

        let signedRate: Double = {
            switch direction {
            case .lose:     return -abs(rateKg)
            case .gain:     return abs(rateKg)
            case .maintain: return 0
            }
        }()

        let goal = WeightGoal(
            direction: direction,
            startingKilograms: startingKg,
            targetKilograms: targetKg,
            weeklyRateKilograms: signedRate,
            startDate: existing?.startDate ?? .now
        )
        WeightGoalStore.shared.set(goal)
        dismiss()
    }
}
