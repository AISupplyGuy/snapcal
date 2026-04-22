import SwiftUI

// Insights — longitudinal view. Future fills: weight trend from
// HealthKit, 7/30/90-day macro averages vs goals, goal-attainment
// streak, most-logged foods, weight-vs-calories overlay, sleep/HRV
// correlations later. Track = today. Insights = weeks/months.
struct InsightsView: View {
    private let diary = MealDiary.shared
    private let goals = GoalsStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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

                    quickStatsCard

                    ComingSoonCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Weight trend",
                        copy: "Read-only overlay from Apple Health, plotted against your average daily calories."
                    )
                    ComingSoonCard(
                        icon: "flame.fill",
                        title: "Goal attainment",
                        copy: "Consecutive days within ±10% of your calorie target. Forgiving enough to survive real life."
                    )
                    ComingSoonCard(
                        icon: "rectangle.stack.fill",
                        title: "Most-logged foods",
                        copy: "Which foods you eat the most, and which are getting smarter over time as calibration learns them."
                    )
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("")
        }
    }

    // Preview of the live numbers we already have. Real weight + HealthKit
    // overlays slot in here once the HealthKit client ships.
    private var quickStatsCard: some View {
        let totals = diary.dailyTotals
        let target = goals.goals.calories
        let delta = target > 0 ? Int((totals.calories - target)) : 0
        return VStack(alignment: .leading, spacing: 14) {
            Text("Today at a glance")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                statCell(
                    value: "\(Int(totals.calories))",
                    label: "Consumed",
                    tint: SCTheme.Colors.accentOrange
                )
                statCell(
                    value: "\(Int(target))",
                    label: "Goal",
                    tint: .primary
                )
                statCell(
                    value: "\(delta >= 0 ? "+" : "")\(delta)",
                    label: "Delta",
                    tint: delta > 0 ? SCTheme.Colors.accentPink : SCTheme.Colors.carbGreen
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private func statCell(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    InsightsView()
}
