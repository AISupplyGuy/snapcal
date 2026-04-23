import SwiftUI
import Charts

// Insights — longitudinal view. Fills today: 7/30-day calorie chart,
// macro averages, goal attainment streak, day streak, most-logged foods.
// Weight trend still waits on HealthKit.
struct InsightsView: View {
    private let diary = MealDiary.shared
    private let goalsStore = GoalsStore.shared

    @State private var range: InsightsRange = .week
    @State private var snapshot: InsightsSnapshot = Self.placeholder

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    rangePicker
                    caloriesCard
                    macrosCard
                    streaksRow
                    mostLoggedCard
                    weightPlaceholderCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("")
            .onAppear(perform: recompute)
            .onChange(of: range) { _, _ in recompute() }
        }
    }

    private func recompute() {
        snapshot = InsightsAggregator.snapshot(
            meals: diary.allMeals(),
            goals: goalsStore.goals,
            dayStreak: diary.dayStreak,
            windowDays: range.days
        )
    }

    private static let placeholder = InsightsSnapshot(
        days: [],
        averageCalories: 0,
        averageProtein: 0,
        averageCarbs: 0,
        averageFat: 0,
        goalAttainmentStreak: 0,
        dayStreak: 0,
        mostLogged: [],
        totalMealsLogged: 0
    )

    // MARK: - Blocks

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(text: "Insights", tint: SCTheme.Colors.proteinBlue)
            Text("Your patterns")
                .font(SCTheme.Type_.title(30))
                .foregroundStyle(.primary)
            Text("Weight, macros, and streaks over weeks, not hours. Track shows today. Insights shows whether it's adding up.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(InsightsRange.allCases, id: \.self) { r in
                Text(r.label).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }

    private var caloriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calories")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(Int(snapshot.averageCalories))")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                    Text("avg")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if snapshot.days.isEmpty {
                emptyChart
            } else {
                caloriesChart
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    // Axis label cadence. 7-day range shows narrow weekday letters; 30-day
    // uses month/day every 5 days so "TWTFSSM..." doesn't mush together.
    private var caloriesChart: some View {
        let goal = goalsStore.goals.calories
        let stride = range == .week ? 1 : 5
        return Chart {
            ForEach(snapshot.days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Calories", day.calories),
                    width: .ratio(0.65)
                )
                .foregroundStyle(
                    day.calories >= goal * 0.9 && day.calories <= goal * 1.1
                        ? SCTheme.Colors.carbGreen
                        : SCTheme.Colors.accentOrange
                )
                .cornerRadius(4)
            }
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(SCTheme.Colors.accentPink.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 180)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: stride)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.primary.opacity(0.15))
                if range == .week {
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                AxisValueLabel()
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .chartOverlay { proxy in
            // Floating goal label pinned inside the plot area — avoids the
            // right-edge clipping that .annotation(.topTrailing) had.
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame,
                   let y = proxy.position(forY: goal) {
                    let frame = geo[plotFrame]
                    Text("Goal \(Int(goal))")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentPink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(SCTheme.Colors.accentPink.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(SCTheme.Colors.accentPink.opacity(0.35), lineWidth: 0.5))
                        .position(
                            x: frame.minX + 42,
                            y: max(frame.minY + 10, y - 10)
                        )
                }
            }
        }
    }

    private var emptyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No data yet")
                .font(SCTheme.Type_.cardTitle())
                .foregroundStyle(.primary)
            Text("Log a few meals and this chart fills in.")
                .font(SCTheme.Type_.caption())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
    }

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Average macros")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                macroPill(
                    label: "Protein",
                    avg: snapshot.averageProtein,
                    goal: goalsStore.goals.proteinGrams,
                    tint: SCTheme.Colors.proteinBlue,
                    soft: SCTheme.Colors.proteinSoft
                )
                macroPill(
                    label: "Carbs",
                    avg: snapshot.averageCarbs,
                    goal: goalsStore.goals.carbGrams,
                    tint: SCTheme.Colors.carbGreen,
                    soft: SCTheme.Colors.carbSoft
                )
                macroPill(
                    label: "Fat",
                    avg: snapshot.averageFat,
                    goal: goalsStore.goals.fatGrams,
                    tint: SCTheme.Colors.accentOrange,
                    soft: SCTheme.Colors.caloriesSoft
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private func macroPill(
        label: String,
        avg: Double,
        goal: Double,
        tint: Color,
        soft: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(tint)
            Text("\(Int(avg))g")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text("of \(Int(goal))g")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(soft, in: RoundedRectangle(cornerRadius: 12))
    }

    private var streaksRow: some View {
        HStack(spacing: 10) {
            streakCell(
                value: "\(snapshot.dayStreak)",
                label: "Logging streak",
                caption: "days in a row",
                tint: SCTheme.Colors.accentOrange
            )
            streakCell(
                value: "\(snapshot.goalAttainmentStreak)",
                label: "On-target streak",
                caption: "within ±10% of calorie goal",
                tint: SCTheme.Colors.carbGreen
            )
        }
    }

    private func streakCell(value: String, label: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .scCardStyle()
    }

    private var mostLoggedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Most logged")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.totalMealsLogged) meals total")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            }

            if snapshot.mostLogged.isEmpty {
                Text("Log a few meals and we'll show what you eat most.")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(snapshot.mostLogged) { food in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(SCTheme.Colors.accentOrange.opacity(0.18))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("\(food.count)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(SCTheme.Colors.accentOrange)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(food.name)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("last \(relative(food.lastSeen))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private var weightPlaceholderCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "scalemass.fill")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.proteinBlue)
                .frame(width: 38, height: 38)
                .background(SCTheme.Colors.proteinBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Weight trend")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("SOON")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(SCTheme.Colors.accentPink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SCTheme.Colors.accentPink.opacity(0.12), in: Capsule())
                }
                Text("Connect Apple Health in Profile to overlay weight on top of daily calories.")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .scCardStyle()
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: .now)
    }
}

enum InsightsRange: CaseIterable {
    case week, month

    var label: String {
        switch self {
        case .week:  return "7 days"
        case .month: return "30 days"
        }
    }

    var days: Int {
        switch self {
        case .week:  return 7
        case .month: return 30
        }
    }
}

#Preview {
    InsightsView()
}
