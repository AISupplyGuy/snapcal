import SwiftUI

// Replaces the old IdlePrompt. Shows today's daily totals + ring and the list
// of meals already logged today, plus the primary "Snap a meal" CTA.
// Reads from the shared MealDiary so saves from elsewhere update in place.

struct TodayView: View {
    let onTapCamera: () -> Void
    private let diary = MealDiary.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                dailyRing
                if diary.todaysMeals.isEmpty {
                    emptyState
                } else {
                    mealsList
                }
                snapCTA
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(text: "Today", tint: SCTheme.Colors.accentOrange)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.dateFormatter.string(from: .now))
                    .font(SCTheme.Type_.title(32))
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMMd")
        return f
    }()

    // MARK: Daily ring

    private var dailyRing: some View {
        let totals = diary.dailyTotals
        return VStack(spacing: 16) {
            ZStack {
                DailyRings(
                    calories: totals.calories,
                    protein: totals.proteinGrams,
                    carbs: totals.carbGrams
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
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                SCMacroChip(
                    label: "Protein",
                    value: "\(Int(totals.proteinGrams))g",
                    tint: SCTheme.Colors.proteinBlue,
                    softBg: SCTheme.Colors.proteinSoft
                )
                SCMacroChip(
                    label: "Carbs",
                    value: "\(Int(totals.carbGrams))g",
                    tint: SCTheme.Colors.carbGreen,
                    softBg: SCTheme.Colors.carbSoft
                )
                SCMacroChip(
                    label: "Fat",
                    value: "\(Int(totals.fatGrams))g",
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

    private var mealsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meals")
                .font(SCTheme.Type_.kicker())
                .tracking(1.2)
                .foregroundStyle(.secondary)
            ForEach(diary.todaysMeals) { meal in
                TodayMealRow(meal: meal)
            }
        }
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
                Text(meal.mealName)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
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

    // Rough daily targets for visual progress only. Real targets come later with
    // goals/onboarding; until then these give the rings somewhere to fill.
    private let calorieTarget: Double = 2200
    private let proteinTarget: Double = 150
    private let carbTarget: Double = 250

    var body: some View {
        ZStack {
            Ring(progress: calories / calorieTarget, color: SCTheme.Colors.accentPink, thickness: 18)
            Ring(progress: protein / proteinTarget, color: SCTheme.Colors.proteinBlue, thickness: 18)
                .padding(20)
            Ring(progress: carbs / carbTarget, color: SCTheme.Colors.carbGreen, thickness: 18)
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
