import SwiftUI

// Two states stacked behind a NavigationLink push:
//
//   1. Browse — full recipe at-a-glance (hero, macro chart, ingredients
//      list with pantry indicators, expandable steps). "Start cooking"
//      pushes into:
//   2. CookMode — full-screen step-at-a-time view with timer per step
//      and a live macro tally pinned at the bottom. The user advances
//      with a swipe or "Next step." Final step shows "I cooked it" which
//      logs to MealDiary and dismisses back to the recipe.
struct RecipeDetailView: View {
    let recipe: Recipe

    @State private var store = RecipeStore.shared
    @State private var startingCookMode = false
    @State private var ingredientsExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                meta
                macroBreakdown
                ingredientsCard
                stepsCard
                logManuallyButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background(.background)
        .safeAreaInset(edge: .bottom) {
            startCookingButton
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .background(.ultraThinMaterial)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.toggleSaved(recipe)
                } label: {
                    Image(systemName: store.isSaved(recipe) ? "heart.fill" : "heart")
                        .foregroundStyle(SCTheme.Colors.accentPink)
                }
            }
        }
        .navigationDestination(isPresented: $startingCookMode) {
            CookModeView(recipe: recipe)
        }
        .onAppear { TabBarFadeModel.shared.opacity = 0 }
        .onDisappear { TabBarFadeModel.shared.reset() }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(gradient)
                .frame(height: 220)
                .shadow(color: shadowTint.opacity(0.32), radius: 16, y: 8)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.name)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                    Text(recipe.summary)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: recipe.symbol)
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(18)
        }
    }

    private var gradient: LinearGradient {
        switch recipe.palette {
        case .sunset: return LinearGradient(colors: [SCTheme.Colors.accentPink, SCTheme.Colors.accentOrange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .grove:  return LinearGradient(colors: [SCTheme.Colors.carbGreen, Color(hex: 0x16A34A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ocean:  return LinearGradient(colors: [SCTheme.Colors.proteinBlue, Color(hex: 0x5856D6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .berry:  return LinearGradient(colors: [Color(hex: 0xBF5AF2), SCTheme.Colors.accentPink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ember:  return LinearGradient(colors: [Color(hex: 0xFF6B35), Color(hex: 0xC42D52)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    private var shadowTint: Color {
        switch recipe.palette {
        case .sunset: return SCTheme.Colors.accentPink
        case .grove:  return SCTheme.Colors.carbGreen
        case .ocean:  return SCTheme.Colors.proteinBlue
        case .berry:  return Color(hex: 0xBF5AF2)
        case .ember:  return SCTheme.Colors.accentOrange
        }
    }

    // MARK: Meta

    private var meta: some View {
        HStack(spacing: 8) {
            metaPill(icon: "clock.fill", value: "\(recipe.totalMinutes)", label: "min")
            metaPill(icon: "person.2.fill", value: "\(recipe.servings)", label: "servings")
            metaPill(icon: "flame.fill", value: recipe.difficulty.label, label: "level")
            metaPill(icon: "cabinet.fill",
                     value: "\(recipe.ingredients.filter { $0.fromPantry }.count)/\(recipe.ingredients.count)",
                     label: "from pantry")
        }
    }

    private func metaPill(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(SCTheme.Colors.accentPink)
                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .scCardStyle()
    }

    // MARK: Macros

    private var macroBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PER SERVING")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(recipe.perServing.calories))")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                    Text("kcal")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                macroBlock("Protein", value: recipe.perServing.proteinGrams, tint: SCTheme.Colors.proteinBlue, soft: SCTheme.Colors.proteinSoft)
                macroBlock("Carbs", value: recipe.perServing.carbGrams, tint: SCTheme.Colors.carbGreen, soft: SCTheme.Colors.carbSoft)
                macroBlock("Fat", value: recipe.perServing.fatGrams, tint: SCTheme.Colors.accentPink, soft: SCTheme.Colors.accentPink.opacity(0.12))
            }
        }
        .padding(16)
        .scCardStyle()
    }

    private func macroBlock(_ label: String, value: Double, tint: Color, soft: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(tint.opacity(0.85))
            Text("\(Int(value))g")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.75)
        )
    }

    // MARK: Ingredients

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("INGREDIENTS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { ingredientsExpanded.toggle() }
                } label: {
                    Image(systemName: ingredientsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if ingredientsExpanded {
                VStack(spacing: 8) {
                    ForEach(recipe.ingredients) { ingredient in
                        IngredientRow(ingredient: ingredient)
                    }
                }
            }
        }
        .padding(16)
        .scCardStyle()
    }

    // MARK: Steps

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STEPS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(recipe.steps.count) steps")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(recipe.steps) { step in
                    StepRow(step: step)
                }
            }
        }
        .padding(16)
        .scCardStyle()
    }

    // MARK: Footer

    private var startCookingButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            startingCookMode = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("Start cooking")
            }
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(SCTheme.Gradients.cta, in: Capsule())
            .shadow(color: SCTheme.Colors.accentPink.opacity(0.32), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var logManuallyButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            logToTrack(recipe: recipe, servings: 1)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                Text("Already cooked? Log 1 serving")
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(SCTheme.Colors.accentPink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(SCTheme.Colors.accentPink.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// Hooked from both the manual "log 1 serving" button and from CookMode's
// "I cooked it" CTA. Builds a single-item MealEntry whose nutrition was
// already computed from USDA at recipe-generation time so the Track tab
// shows the same numbers the recipe promised.
@MainActor
func logToTrack(recipe: Recipe, servings: Double) {
    let totalGrams = max(0, recipe.ingredients
        .map { RecipeNutritionCalculator.gramsApproximation(quantity: $0.quantity, unit: $0.unit, name: $0.name) }
        .reduce(0, +))
    let perServingGrams = totalGrams / Double(max(1, recipe.servings))
    let nutrition = recipe.perServing.scaled(by: servings)
    let item = MealItem(
        name: recipe.name,
        portionAmount: servings,
        portionUnit: .piece,
        gramsEstimate: perServingGrams * servings,
        usdaFdcId: nil,
        usdaDescription: recipe.name,
        matchedSourceId: "recipe",
        matchConfidence: 0.9,
        nutrition: nutrition,
        baselinePer100g: .zero,
        itemConfidence: 0.9,
        preparation: nil,
        brandCue: nil
    )
    let meal = MealEntry(
        mealName: recipe.name,
        plateContext: .home,
        referenceObjectPresent: false,
        overallConfidence: 0.9,
        items: [item],
        modelTier: "recipe",
        needsVerification: false
    )
    MealDiary.shared.save(meal)
}

// MARK: - Ingredient row

private struct IngredientRow: View {
    let ingredient: RecipeIngredient

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(ingredient.fromPantry
                          ? SCTheme.Colors.carbGreen.opacity(0.18)
                          : Color.primary.opacity(0.06))
                Image(systemName: ingredient.fromPantry ? "checkmark" : "minus")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(ingredient.fromPantry ? SCTheme.Colors.carbGreen : .secondary)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.displayName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(quantityLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let perServing = ingredient.perServing {
                Text("\(Int(perServing.calories)) kcal")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var quantityLabel: String {
        let q = ingredient.quantity.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(ingredient.quantity))
            : String(format: "%.2g", ingredient.quantity)
        return "\(q) \(ingredient.unit)"
    }
}

// MARK: - Step row

private struct StepRow: View {
    let step: RecipeStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(SCTheme.Colors.accentPink.opacity(0.14))
                Text("\(step.index)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(SCTheme.Colors.accentPink)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.instruction)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let timerSeconds = step.timerSeconds {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .heavy))
                        Text(formattedTimer(timerSeconds))
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(SCTheme.Colors.accentOrange)
                }
            }
            Spacer()
        }
    }

    private func formattedTimer(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m)m \(s)s"
    }
}
