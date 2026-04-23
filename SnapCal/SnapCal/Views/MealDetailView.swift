import SwiftUI

// Read-only view of a saved meal — what the user taps into from Track's
// meal list. Shows the same breakdown that MealCardView shows pre-save
// (photo, items, macros), minus the sliders. Users can still delete
// from here (mirrors the swipe-to-delete on the row).
struct MealDetailView: View {
    let meal: MealEntry
    @State private var showingDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if meal.needsVerification {
                    verificationBanner
                }
                totalsCard
                itemsList
                metadataCard
                deleteButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this meal?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                MealDiary.shared.delete(meal)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(meal.mealName) from your log. This can't be undone.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SCKickerPill(text: "Logged meal", tint: SCTheme.Colors.accentOrange)
                Text(Self.timeFormatter.string(from: meal.capturedAt))
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            }
            Text(meal.mealName)
                .font(SCTheme.Type_.title(28))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: Verification banner

    private var verificationBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.accentOrange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Flagged for verification")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text("The photo was ambiguous, so Flash and Pro disagreed on totals. Numbers here are a best estimate.")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SCTheme.Radius.md)
                .fill(SCTheme.Colors.accentOrange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SCTheme.Radius.md)
                .stroke(SCTheme.Colors.accentOrange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Totals

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total calories")
                        .font(SCTheme.Type_.kicker())
                        .tracking(1.0)
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(meal.totals.calories))")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(SCTheme.Gradients.heroText)
                        Text("kcal")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
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
            ForEach(meal.items) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: MealItem) -> some View {
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
                    if let source = item.matchedSourceId, source != "usda" {
                        HStack(spacing: 3) {
                            Image(systemName: "storefront.fill")
                                .font(.system(size: 9))
                            Text("via \(source)")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(SCTheme.Colors.accentPink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SCTheme.Colors.accentPink.opacity(0.12), in: Capsule())
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

    // MARK: Metadata

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected by")
                .font(SCTheme.Type_.kicker())
                .tracking(1.2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(SCTheme.Colors.proteinBlue)
                Text(modelTierLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(meal.overallConfidence * 100))% confidence")
                    .font(SCTheme.Type_.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    private var modelTierLabel: String {
        switch meal.modelTier {
        case "flash":     return "Gemini Flash"
        case "pro":       return "Gemini Pro"
        case "flash+pro": return "Flash + Pro (divergent)"
        default:          return meal.modelTier.capitalized
        }
    }

    // MARK: Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Label("Delete meal", systemImage: "trash")
                .font(SCTheme.Type_.button())
                .foregroundStyle(SCTheme.Colors.accentPink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: SCTheme.Radius.md)
                        .stroke(SCTheme.Colors.accentPink.opacity(0.35), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}
