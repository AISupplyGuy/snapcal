import SwiftUI
import Charts

// Track tab. Single scrollable page: today's rings + meals, weight
// log/chart, then a summary of goals with a deep link to Profile >
// Daily Targets for editing. Reads from MealDiary / WeightLog /
// GoalsStore so saves from elsewhere update in place.

struct TodayView: View {
    let onTapCamera: () -> Void
    let lidarEnabled: Bool
    private let diary = MealDiary.shared
    private let goalsStore = GoalsStore.shared
    private let weightLog = WeightLog.shared
    @State private var goalStore = WeightGoalStore.shared

    @State private var showingLogWeight = false
    @State private var showingEditGoal = false
    @AppStorage(ProfilePrefsKeys.weightUnit) private var weightUnitRaw = WeightUnit.pounds.rawValue

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .pounds }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .padding(.top, 4)

                dailyRing

                if diary.todaysMeals.isEmpty {
                    emptyState
                        .padding(.top, 4)
                } else {
                    Text("Meals")
                        .font(SCTheme.Type_.kicker())
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    ForEach(diary.todaysMeals) { meal in
                        NavigationLink {
                            MealDetailView(meal: meal)
                        } label: {
                            TodayMealRow(meal: meal)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                diary.delete(meal)
                            } label: {
                                Label("Delete meal", systemImage: "trash")
                            }
                        }
                    }
                }

                weightCard
                    .padding(.top, 12)

                weightGoalCard
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .tabBarFadesOnScroll(scale: 2.0)
        .sheet(isPresented: $showingLogWeight) {
            LogWeightSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingEditGoal) {
            EditWeightGoalSheet(existing: goalStore.goal)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Weight

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight")
                        .font(SCTheme.Type_.kicker())
                        .tracking(1.0)
                        .foregroundStyle(SCTheme.Colors.proteinBlue)
                    if let latest = weightLog.latest {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatWeight(latest))
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(weightUnit.label)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        if let delta = weightLog.change(overLastDays: 30, unit: weightUnit) {
                            let up = delta >= 0
                            Text("\(up ? "+" : "")\(String(format: "%.1f", delta)) \(weightUnit.label) in 30 days")
                                .font(SCTheme.Type_.caption())
                                .foregroundStyle(up ? SCTheme.Colors.accentPink : SCTheme.Colors.carbGreen)
                        }
                    } else {
                        Text("No weight logged yet")
                            .font(SCTheme.Type_.cardTitle())
                            .foregroundStyle(.primary)
                    }
                }
                Spacer()
                Button {
                    showingLogWeight = true
                } label: {
                    Label("Log", systemImage: "plus")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentPink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(SCTheme.Colors.accentPink.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if weightLog.entries.count >= 2 {
                weightChart
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private var weightChart: some View {
        let recent = Array(weightLog.entries.suffix(30))
        return Chart {
            ForEach(recent) { entry in
                LineMark(
                    x: .value("Date", entry.measuredAt),
                    y: .value(weightUnit.label, weightUnit == .kilograms ? entry.kilograms : entry.pounds)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(SCTheme.Colors.proteinBlue)
                PointMark(
                    x: .value("Date", entry.measuredAt),
                    y: .value(weightUnit.label, weightUnit == .kilograms ? entry.kilograms : entry.pounds)
                )
                .foregroundStyle(SCTheme.Colors.proteinBlue)
                .symbolSize(24)
            }
        }
        .frame(height: 120)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.primary.opacity(0.05))
                AxisValueLabel().foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, recent.count / 4))) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatWeight(_ entry: WeightEntry) -> String {
        let value = weightUnit == .kilograms ? entry.kilograms : entry.pounds
        return String(format: "%.1f", value)
    }

    // MARK: Weight goal

    private var weightGoalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("GOAL")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingEditGoal = true
                } label: {
                    HStack(spacing: 4) {
                        Text(goalStore.goal == nil ? "Set" : "Edit")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(SCTheme.Colors.accentPink)
                }
                .buttonStyle(.plain)
            }

            if let goal = goalStore.goal, let current = weightLog.latest?.kilograms {
                weightGoalContent(goal: goal, current: current)
            } else {
                goalEmptyState
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private var goalEmptyState: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.accentPink)
                .frame(width: 40, height: 40)
                .background(SCTheme.Colors.accentPink.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(weightLog.latest == nil ? "Log a weight first" : "Set a weight goal")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(weightLog.latest == nil
                     ? "Tap Log above, then come back here to set where you're headed."
                     : "Pick a target and a weekly pace. We'll cheer you on the whole way there.")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func weightGoalContent(goal: WeightGoal, current: Double) -> some View {
        let progress = goal.progress(currentKilograms: current)
        let pace = goal.observedWeeklyPace(currentKilograms: current)
        let targetDisplay = weightUnit == .kilograms ? goal.targetKilograms : goal.targetKilograms * 2.20462
        let currentDisplay = weightUnit == .kilograms ? current : current * 2.20462
        let remaining = remainingDisplay(goal: goal, current: current)
        let paceDisplay = weightUnit == .kilograms ? pace : pace * 2.20462
        let targetPace = weightUnit == .kilograms ? goal.weeklyRateKilograms : goal.weeklyRateKilograms * 2.20462

        return VStack(alignment: .leading, spacing: 14) {
            // Motivational headline — adapts to progress.
            Text(motivationalHeadline(progress: progress, goal: goal))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Current vs target.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", currentDisplay)) \(weightUnit.label)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", targetDisplay)) \(weightUnit.label)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentPink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("To go")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                    Text(remaining)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                }
            }

            // Progress bar with milestones.
            progressTrack(progress: progress)

            // Pace line.
            if goal.direction != .maintain {
                paceLine(pace: paceDisplay, target: targetPace)
            }

            // Milestone badges.
            milestoneRow(progress: progress)
        }
    }

    private func progressTrack(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(SCTheme.Gradients.cta)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 10)
    }

    private func paceLine(pace: Double, target: Double) -> some View {
        let onPace: Bool = {
            guard target != 0 else { return true }
            // Same direction as target, within 40% of absolute magnitude.
            if pace.sign != target.sign { return false }
            let ratio = abs(pace) / abs(target)
            return ratio >= 0.6 && ratio <= 1.4
        }()
        let label: String = {
            if pace == 0 { return "Awaiting data…" }
            let sign = pace >= 0 ? "+" : ""
            return "\(sign)\(String(format: "%.1f", pace)) \(weightUnit.label)/week"
        }()
        return HStack(spacing: 8) {
            Image(systemName: onPace ? "checkmark.seal.fill" : "hare.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(onPace ? SCTheme.Colors.carbGreen : SCTheme.Colors.accentOrange)
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text(onPace ? "on pace" : "adjusting")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func milestoneRow(progress: Double) -> some View {
        HStack(spacing: 6) {
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { milestone in
                let hit = progress >= milestone
                HStack(spacing: 4) {
                    Image(systemName: hit ? "rosette" : "circle")
                        .font(.system(size: 11, weight: .heavy))
                    Text(milestoneLabel(milestone))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(hit ? SCTheme.Colors.accentPink : Color.secondary.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (hit ? SCTheme.Colors.accentPink : Color.secondary)
                        .opacity(hit ? 0.14 : 0.08),
                    in: Capsule()
                )
            }
        }
    }

    private func milestoneLabel(_ fraction: Double) -> String {
        if fraction >= 1.0 { return "Goal" }
        return "\(Int(fraction * 100))%"
    }

    private func motivationalHeadline(progress: Double, goal: WeightGoal) -> String {
        if goal.direction == .maintain {
            return progress >= 1 ? "Holding steady. Locked in." : "Stay the course."
        }
        switch progress {
        case ..<0.05:  return "Day one. Let's go."
        case ..<0.25:  return "Early momentum. Keep stacking days."
        case ..<0.5:   return "Real progress. You're building the habit."
        case ..<0.75:  return "Over halfway. Don't look back now."
        case ..<1.0:   return "Almost there. Closing in on the target."
        default:       return "Goal hit. Pick a new one when you're ready."
        }
    }

    private func remainingDisplay(goal: WeightGoal, current: Double) -> String {
        let remainingKg: Double
        switch goal.direction {
        case .lose:     remainingKg = max(0, current - goal.targetKilograms)
        case .gain:     remainingKg = max(0, goal.targetKilograms - current)
        case .maintain: remainingKg = abs(current - goal.targetKilograms)
        }
        let display = weightUnit == .kilograms ? remainingKg : remainingKg * 2.20462
        return "\(String(format: "%.1f", display)) \(weightUnit.label)"
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SCKickerPill(text: "Track", tint: SCTheme.Colors.accentOrange)
                if lidarEnabled {
                    SCKickerPill(text: "LiDAR enabled", tint: SCTheme.Colors.standTeal)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.dateFormatter.string(from: .now))
                    .font(SCTheme.Type_.title(32))
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMMd")
        return f
    }()

    // MARK: Daily ring

    private var dailyRing: some View {
        let totals = diary.dailyTotals
        let goals = goalsStore.goals
        return VStack(spacing: 16) {
            ZStack {
                DailyRings(
                    calories: totals.calories,
                    protein: totals.proteinGrams,
                    carbs: totals.carbGrams,
                    calorieTarget: goals.calories,
                    proteinTarget: goals.proteinGrams,
                    carbTarget: goals.carbGrams
                )
                .frame(width: 180, height: 180)
                VStack(spacing: 0) {
                    Text("\(Int(totals.calories))")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Gradients.heroText)
                        .contentTransition(.numericText(value: totals.calories))
                        .animation(.easeOut(duration: 0.2), value: totals.calories)
                    Text("kcal")
                        .font(SCTheme.Type_.kicker())
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Text("of \(Int(goals.calories))")
                        .font(SCTheme.Type_.caption())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                SCMacroChip(
                    label: "Protein",
                    value: "\(Int(totals.proteinGrams))/\(Int(goals.proteinGrams))g",
                    tint: SCTheme.Colors.proteinBlue,
                    softBg: SCTheme.Colors.proteinSoft
                )
                SCMacroChip(
                    label: "Carbs",
                    value: "\(Int(totals.carbGrams))/\(Int(goals.carbGrams))g",
                    tint: SCTheme.Colors.carbGreen,
                    softBg: SCTheme.Colors.carbSoft
                )
                SCMacroChip(
                    label: "Fat",
                    value: "\(Int(totals.fatGrams))/\(Int(goals.fatGrams))g",
                    tint: SCTheme.Colors.accentOrange,
                    softBg: SCTheme.Colors.caloriesSoft
                )
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .scCardStyle()
    }

    // MARK: Empty / list

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No meals yet today")
                .font(SCTheme.Type_.cardTitle())
                .foregroundStyle(.primary)
            Text("Snap a plate to get started. Calories come from USDA's verified database.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .scCardStyle()
    }

}

// MARK: - Meal row (one per logged meal)

private struct TodayMealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(meal.mealName)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if meal.needsVerification {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(SCTheme.Colors.accentOrange)
                            .accessibilityLabel("Needs verification")
                    }
                }
                Text(timeText)
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(meal.totals.calories))")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(SCTheme.Colors.accentOrange)
                Text("kcal")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .scCardStyle()
    }

    private var timeText: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: meal.capturedAt)
    }
}

// MARK: - Apple-style concentric rings

private struct DailyRings: View {
    let calories: Double
    let protein: Double
    let carbs: Double

    let calorieTarget: Double
    let proteinTarget: Double
    let carbTarget: Double

    var body: some View {
        ZStack {
            Ring(progress: calories / max(calorieTarget, 1), color: SCTheme.Colors.accentPink, thickness: 18)
            Ring(progress: protein / max(proteinTarget, 1), color: SCTheme.Colors.proteinBlue, thickness: 18)
                .padding(20)
            Ring(progress: carbs / max(carbTarget, 1), color: SCTheme.Colors.carbGreen, thickness: 18)
                .padding(40)
        }
    }
}

private struct Ring: View {
    let progress: Double
    let color: Color
    let thickness: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: thickness)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)
        }
    }
}
