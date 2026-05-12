import SwiftUI

struct EditWeightGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProfilePrefsKeys.weightUnit) private var unitRaw = WeightUnit.pounds.rawValue

    @State private var direction: WeightGoal.Direction
    @State private var targetString: String
    @State private var weeklyRateString: String
    @State private var saveHapticTrigger = 0
    @FocusState private var targetFocused: Bool

    private let existing: WeightGoal?
    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .pounds }
    private var currentKg: Double? { WeightLog.shared.latest?.kilograms }

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
            _weeklyRateString = State(initialValue: String(format: "%.1f", abs(rateDisplay)))
        } else {
            _targetString = State(initialValue: "")
            _weeklyRateString = State(initialValue: "1.0")
        }
    }

    private var parsedTarget: Double? { Double(targetString.trimmingCharacters(in: .whitespaces)) }
    private var parsedRate: Double? { Double(weeklyRateString.trimmingCharacters(in: .whitespaces)) }
    private var canSave: Bool {
        currentKg != nil && (parsedTarget ?? 0) > 0 && (parsedRate ?? 0) >= 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            ambient
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        directionCard
                        targetCard
                        if direction != .maintain {
                            paceCard
                        }
                        if currentKg == nil {
                            noWeightCard
                        }
                        if existing != nil {
                            removeButton
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: saveHapticTrigger)
    }

    // MARK: Ambient

    private var ambient: some View {
        ZStack {
            RadialGradient(
                colors: [SCTheme.Colors.accentPink.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 380
            )
            RadialGradient(
                colors: [SCTheme.Colors.accentOrange.opacity(0.12), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
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
            SCKickerPill(text: existing == nil ? "New goal" : "Edit goal", tint: SCTheme.Colors.accentPink)
            Text(existing == nil ? "Set a weight goal" : "Tune your goal")
                .font(SCTheme.Type_.title(28))
                .foregroundStyle(.primary)
            Text(directionFooter)
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: Direction card

    private var directionCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Direction")
                HStack(spacing: 4) {
                    ForEach(WeightGoal.Direction.allCases) { d in
                        Button {
                            direction = d
                        } label: {
                            Text(d.label)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(direction == d ? .white : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background {
                                    if direction == d {
                                        Capsule().fill(SCTheme.Gradients.cta)
                                            .shadow(color: SCTheme.Colors.accentPink.opacity(0.35), radius: 6, y: 3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Capsule().fill(.white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.06)))
            }
        }
    }

    // MARK: Target card

    private var targetCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                fieldLabel(direction == .maintain ? "Maintain at" : "Target")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0.0", text: $targetString)
                        .keyboardType(.decimalPad)
                        .focused($targetFocused)
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .tracking(-1.2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(unit.label)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if direction == .maintain {
                    Text("We'll flag the goal as hit when you're within 2 \(unit.label) of target.")
                        .font(SCTheme.Type_.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Pace card

    private var paceCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                fieldLabel("Pace")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(direction == .lose ? "−" : "+")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(direction == .lose ? SCTheme.Colors.accentPink : SCTheme.Colors.carbGreen)
                    TextField("0.0", text: $weeklyRateString)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(unit.label)/week")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text("A safe rate for most people is 0.5–1.0 \(unit.label)/week in either direction.")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: No-weight notice

    private var noWeightCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.accentOrange)
            Text("Log a current weight on Track before saving a goal.")
                .font(SCTheme.Type_.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                .fill(SCTheme.Colors.accentOrange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SCTheme.Radius.md, style: .continuous)
                .strokeBorder(SCTheme.Colors.accentOrange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Remove

    private var removeButton: some View {
        Button {
            WeightGoalStore.shared.clear()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                Text("Remove goal")
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(SCTheme.Colors.accentPink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(SCTheme.Colors.accentPink.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(SCTheme.Colors.accentPink.opacity(0.3), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Button {
                saveHapticTrigger &+= 1
                save()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(existing == nil ? "Save goal" : "Update goal")
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
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: Helpers

    private var directionFooter: String {
        switch direction {
        case .lose:     return "Pick a lower target and a weekly pace. We'll track progress against today's starting weight."
        case .gain:     return "Pick a higher target and a weekly pace. We'll track progress against today's starting weight."
        case .maintain: return "Pick the weight you want to hold. A ±2 \(unit.label) band counts as on-target."
        }
    }

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
