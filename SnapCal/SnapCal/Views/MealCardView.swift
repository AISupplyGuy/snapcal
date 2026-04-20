import SwiftUI

struct MealCardView: View {
    @State var meal: MealEntry
    let onCommit: (MealEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(meal.mealName).font(.title2).bold()

                totalsCard

                ForEach($meal.items) { $item in
                    ItemRow(item: $item)
                }

                Button {
                    recalculateAndCommit()
                } label: {
                    Text("Save meal").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(Int(meal.totals.calories)) kcal").font(.title3).bold()
                Spacer()
                ConfidenceBadge(confidence: meal.overallConfidence)
            }
            HStack(spacing: 12) {
                macro("P", meal.totals.proteinGrams)
                macro("C", meal.totals.carbGrams)
                macro("F", meal.totals.fatGrams)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func macro(_ label: String, _ grams: Double) -> some View {
        Text("\(label) \(Int(grams))g").font(.footnote).foregroundStyle(.secondary)
    }

    private func recalculateAndCommit() {
        for idx in meal.items.indices {
            let per100 = unscaledPer100g(of: meal.items[idx])
            meal.items[idx].nutrition = per100.scaled(by: meal.items[idx].gramsEstimate / 100.0)
        }
        meal.recomputeTotals()
        onCommit(meal)
    }

    // Reverse-engineer the per-100g numbers so the slider can rescale locally without hitting USDA again.
    private func unscaledPer100g(of item: MealItem) -> NutritionFacts {
        guard item.gramsEstimate > 0 else { return .zero }
        return item.nutrition.scaled(by: 100.0 / item.gramsEstimate)
    }
}

private struct ItemRow: View {
    @Binding var item: MealItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(item.name).font(.headline)
                    if let desc = item.usdaDescription {
                        Text(desc).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                Text("\(Int(item.nutrition.calories)) kcal").font(.subheadline).monospacedDigit()
            }
            HStack {
                Text("\(Int(item.gramsEstimate)) g").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Slider(value: $item.gramsEstimate, in: 5...1000, step: 5)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ConfidenceBadge: View {
    let confidence: Double
    var body: some View {
        let tint: Color = confidence >= 0.7 ? .green : (confidence >= 0.5 ? .orange : .red)
        Text("conf \(Int(confidence * 100))%")
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.2), in: Capsule())
            .foregroundStyle(tint)
    }
}
