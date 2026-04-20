import SwiftUI

struct MealCardView: View {
    @State var meal: MealEntry
    let photo: UIImage?
    let onCommit: (MealEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photoBlock
                headerBlock
                totalsCard
                itemsList
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: Photo

    @ViewBuilder
    private var photoBlock: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: SCTheme.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: SCTheme.Radius.lg)
                        .stroke(.primary.opacity(0.06))
                )
        }
    }

    // MARK: Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SCKickerPill(text: "Logged meal", tint: SCTheme.Colors.accentOrange)
            Text(meal.mealName)
                .font(SCTheme.Type_.title(30))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Totals card

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total calories")
                        .font(SCTheme.Type_.kicker())
                        .tracking(1.0)
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                    Text("\(Int(meal.totals.calories))")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Gradients.heroText)
                    + Text(" kcal")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ConfidenceBadge(confidence: meal.overallConfidence)
            }

            HStack(spacing: 10) {
                SCMacroChip(
                    label: "Protein",
                    value: "\(Int(meal.totals.proteinGrams))g",
                    tint: SCTheme.Colors.proteinBlue,
                    softBg: SCTheme.Colors.proteinSoft
                )
                SCMacroChip(
                    label: "Carbs",
                    value: "\(Int(meal.totals.carbGrams))g",
                    tint: SCTheme.Colors.carbGreen,
                    softBg: SCTheme.Colors.carbSoft
                )
                SCMacroChip(
                    label: "Fat",
                    value: "\(Int(meal.totals.fatGrams))g",
                    tint: SCTheme.Colors.accentOrange,
                    softBg: SCTheme.Colors.caloriesSoft
                )
            }
        }
        .padding(20)
        .scCardStyle()
    }

    // MARK: Items

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Items")
                .font(SCTheme.Type_.kicker())
                .tracking(1.2)
                .foregroundStyle(.secondary)
            ForEach($meal.items) { $item in
                ItemRow(item: $item)
            }
        }
    }

    // MARK: Save

    private var saveButton: some View {
        Button {
            recalculateAndCommit()
        } label: {
            Label("Save meal", systemImage: "checkmark.circle.fill")
                .scCTAStyle()
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: Math

    private func recalculateAndCommit() {
        for idx in meal.items.indices {
            let per100 = unscaledPer100g(of: meal.items[idx])
            meal.items[idx].nutrition = per100.scaled(by: meal.items[idx].gramsEstimate / 100.0)
        }
        meal.recomputeTotals()
        onCommit(meal)
    }

    private func unscaledPer100g(of item: MealItem) -> NutritionFacts {
        guard item.gramsEstimate > 0 else { return .zero }
        return item.nutrition.scaled(by: 100.0 / item.gramsEstimate)
    }
}

// MARK: - Item row

private struct ItemRow: View {
    @Binding var item: MealItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let desc = item.usdaDescription {
                        Text(desc)
                            .font(SCTheme.Type_.caption())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(item.nutrition.calories))")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                    Text("kcal")
                        .font(SCTheme.Type_.caption())
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(Int(item.gramsEstimate))g")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    HStack(spacing: 6) {
                        macroTag("P", Int(item.nutrition.proteinGrams), tint: SCTheme.Colors.proteinBlue)
                        macroTag("C", Int(item.nutrition.carbGrams), tint: SCTheme.Colors.carbGreen)
                        macroTag("F", Int(item.nutrition.fatGrams), tint: SCTheme.Colors.accentOrange)
                    }
                }
                Slider(value: $item.gramsEstimate, in: 5...1000, step: 5)
                    .tint(SCTheme.Colors.accentOrange)
            }
        }
        .padding(16)
        .scCardStyle()
    }

    private func macroTag(_ letter: String, _ grams: Int, tint: Color) -> some View {
        HStack(spacing: 2) {
            Text(letter).font(.system(size: 11, weight: .heavy, design: .rounded))
            Text("\(grams)g").font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Confidence badge

private struct ConfidenceBadge: View {
    let confidence: Double
    var body: some View {
        let tint: Color = confidence >= 0.7
            ? SCTheme.Colors.carbGreen
            : (confidence >= 0.5 ? SCTheme.Colors.accentOrange : SCTheme.Colors.accentPink)
        HStack(spacing: 4) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
            Text("\(Int(confidence * 100))%")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
