import SwiftUI

// Replaces the old IdlePrompt. Shows today's daily totals + ring and the list
// of meals already logged today, plus the primary "Snap a meal" CTA.
// Reads from the shared MealDiary so saves from elsewhere update in place.

struct TodayView: View {
    let onTapCamera: () -> Void
    let lidarEnabled: Bool
    private let diary = MealDiary.shared
    private let goalsStore = GoalsStore.shared

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
                snapCTA
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 24, trailing: 20))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SCKickerPill(text: "Today", tint: SCTheme.Colors.accentOrange)
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

    // MARK: CTA

    private var snapCTA: some View {
        Button(action: onTapCamera) {
            Label("Snap a meal", systemImage: "camera.fill")
                .scCTAStyle()
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
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
