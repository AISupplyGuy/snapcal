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

    @State private var showingLogWeight = false
    @AppStorage(ProfilePrefsKeys.weightUnit) private var weightUnitRaw = WeightUnit.pounds.rawValue

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .pounds }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

            Section {
                dailyRing
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))

            if diary.todaysMeals.isEmpty {
                Section {
                    emptyState
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 0, trailing: 20))
            } else {
                Section {
                    Text("Meals")
                        .font(SCTheme.Type_.kicker())
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))

                    ForEach(diary.todaysMeals) { meal in
                        TodayMealRow(meal: meal)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    diary.delete(meal)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            Section {
                weightCard
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 0, trailing: 20))

            Section {
                goalsSummaryCard
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .sheet(isPresented: $showingLogWeight) {
            LogWeightSheet()
                .presentationDetents([.medium])
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

    // MARK: Goals summary

    private var goalsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("GOALS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    DailyTargetsView()
                } label: {
                    HStack(spacing: 4) {
                        Text("Edit")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(SCTheme.Colors.accentPink)
                }
            }

            let goals = goalsStore.goals
            HStack(spacing: 8) {
                goalPill(label: "kcal", value: Int(goals.calories), tint: SCTheme.Colors.accentPink, soft: SCTheme.Colors.caloriesSoft)
                goalPill(label: "P", value: Int(goals.proteinGrams), tint: SCTheme.Colors.proteinBlue, soft: SCTheme.Colors.proteinSoft)
                goalPill(label: "C", value: Int(goals.carbGrams), tint: SCTheme.Colors.carbGreen, soft: SCTheme.Colors.carbSoft)
                goalPill(label: "F", value: Int(goals.fatGrams), tint: SCTheme.Colors.accentOrange, soft: SCTheme.Colors.caloriesSoft)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private func goalPill(label: String, value: Int, tint: Color, soft: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(soft, in: RoundedRectangle(cornerRadius: 12))
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
