import SwiftUI

// Cook tab. Three states share one shell:
//
//   • Empty — no recents yet. Big "Cook me something" CTA + filter chips.
//   • Browsing — recents exist. Top-of-fold hero card (most recent), then
//     a horizontal recent rail and a vertical saved list.
//   • Generating — full-bleed shimmer card while RecipeGenerator runs.
//
// Tapping a card pushes RecipeDetailView, which owns the cook-mode flow
// (timed steps, macro tally, "I cooked it" auto-log to Track).
//
// Filter chips on the top of every state:
//   - "Use what's expiring" (defaults from PantryStore.expiringSoon)
//   - "Hits my macros" (uses GoalsStore + today's MealDiary totals)
//   - "Quick" (cap to 20 minutes total)
//
// Free tier: 1 generation per day. Hits the paywall after that.
struct CookView: View {
    @State private var store = RecipeStore.shared
    @State private var pantry = PantryStore.shared
    @State private var subs = Subscriptions.shared
    @State private var notificationRouter = NotificationRouter.shared
    @State private var lastSeenCookRequest = 0

    @State private var generating = false
    @State private var generationError: String?
    @State private var paywallTrigger: PaywallTrigger?

    @State private var useExpiring = false
    @State private var hitMacros = true
    @State private var quickOnly = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    filterChips
                    if generating {
                        generatingCard
                    } else if let hero = store.recents.first {
                        heroCard(hero)
                    } else {
                        emptyHero
                    }
                    generateButton
                    if !store.recents.isEmpty {
                        recentsRail
                    }
                    if !store.saved.isEmpty {
                        savedSection
                    }
                    sourceFootnote
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .tabBarFadesOnScroll()
            .navigationTitle("")
            .alert(
                "Couldn't generate recipe",
                isPresented: Binding(get: { generationError != nil }, set: { if !$0 { generationError = nil } })
            ) {
                Button("OK") { generationError = nil }
            } message: {
                Text(generationError ?? "")
            }
            .sheet(item: $paywallTrigger) { trigger in
                PaywallSheet(trigger: trigger.eyebrow, valueProps: trigger.valueProps)
                    .presentationDetents([.large])
            }
            .onChange(of: notificationRouter.cookRequestVersion) { _, new in
                guard new != lastSeenCookRequest else { return }
                lastSeenCookRequest = new
                useExpiring = !notificationRouter.cookSeedIngredients.isEmpty
                Task { await runGeneration() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SCKickerPill(text: "Cook", tint: SCTheme.Colors.accentPink)
            HStack(alignment: .firstTextBaseline) {
                Text("What to eat")
                    .font(SCTheme.Type_.title(30))
                    .foregroundStyle(.primary)
                Spacer()
                engineBadge
            }
            Text("Recipes built from what's in your Pantry and what's left in today's macro budget. Tap one and Cook walks you through it.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var engineBadge: some View {
        let engine = RecipeGenerator.shared.preferredEngine
        let label: String
        let icon: String
        switch engine {
        case .foundation: label = "On-device"; icon = "cpu.fill"
        case .gemini:     label = "Cloud";     icon = "cloud.fill"
        case .unavailable: label = "—";        icon = "exclamationmark.triangle.fill"
        }
        return HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .heavy))
            Text(label).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
        }
        .foregroundStyle(SCTheme.Colors.proteinBlue)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(SCTheme.Colors.proteinBlue.opacity(0.12), in: Capsule())
    }

    // MARK: Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Hits my macros", icon: "scope", on: $hitMacros, tint: SCTheme.Colors.carbGreen)
                FilterChip(
                    label: pantry.expiringSoon().isEmpty ? "Use expiring" : "Use \(pantry.expiringSoon().count) expiring",
                    icon: "clock.badge.exclamationmark.fill",
                    on: $useExpiring,
                    tint: SCTheme.Colors.accentOrange,
                    disabled: pantry.expiringSoon().isEmpty
                )
                FilterChip(label: "Quick", icon: "bolt.fill", on: $quickOnly, tint: SCTheme.Colors.accentPink)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Hero (most recent)

    private func heroCard(_ recipe: Recipe) -> some View {
        NavigationLink {
            RecipeDetailView(recipe: recipe)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    HeroBanner(recipe: recipe)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.toggleSaved(recipe)
                    } label: {
                        Image(systemName: store.isSaved(recipe) ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.28), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(recipe.name)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .tracking(-0.3)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(recipe.summary)
                        .font(SCTheme.Type_.body())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    metaRow(recipe)
                    macroChipsRow(recipe)
                }
                .padding(18)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: SCTheme.Radius.lg))
            .scCardStyle()
        }
        .buttonStyle(.plain)
    }

    private func metaRow(_ recipe: Recipe) -> some View {
        HStack(spacing: 8) {
            metaPill(icon: "clock.fill", text: "\(recipe.totalMinutes) min")
            metaPill(icon: "person.2.fill", text: "\(recipe.servings) servings")
            metaPill(icon: "flame.fill", text: recipe.difficulty.label)
            if recipe.ingredients.contains(where: { $0.fromPantry }) {
                metaPill(icon: "cabinet.fill", text: "Uses pantry", tint: SCTheme.Colors.carbGreen)
            }
        }
    }

    private func metaPill(icon: String, text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .heavy))
            Text(text).font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func macroChipsRow(_ recipe: Recipe) -> some View {
        HStack(spacing: 8) {
            MacroPill(label: "kcal", value: "\(Int(recipe.perServing.calories))",
                      tint: SCTheme.Colors.accentOrange, soft: SCTheme.Colors.caloriesSoft)
            MacroPill(label: "P", value: "\(Int(recipe.perServing.proteinGrams))g",
                      tint: SCTheme.Colors.proteinBlue, soft: SCTheme.Colors.proteinSoft)
            MacroPill(label: "C", value: "\(Int(recipe.perServing.carbGrams))g",
                      tint: SCTheme.Colors.carbGreen, soft: SCTheme.Colors.carbSoft)
            MacroPill(label: "F", value: "\(Int(recipe.perServing.fatGrams))g",
                      tint: SCTheme.Colors.accentPink, soft: SCTheme.Colors.accentPink.opacity(0.12))
        }
    }

    // MARK: Empty hero

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(
                        colors: [SCTheme.Colors.accentPink.opacity(0.18), SCTheme.Colors.accentOrange.opacity(0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(height: 160)
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(SCTheme.Gradients.cta)
            }
            Text("First recipe is on the house.")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text("Cook builds it around what you've got and what you've still got room for. Tap below — takes a couple seconds.")
                .font(SCTheme.Type_.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
    }

    // MARK: Generating skeleton

    private var generatingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(SCTheme.Gradients.cta)
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 38, weight: .heavy))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: SCTheme.Colors.accentPink.opacity(0.25), radius: 14, y: 6)
            }
            HStack(spacing: 8) {
                ProgressView().tint(SCTheme.Colors.accentPink)
                Text("Cooking up your recipe…")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Text("Foundation Models structures the recipe; USDA computes the numbers. Should be a couple seconds.")
                .font(SCTheme.Type_.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scCardStyle()
        .transition(.opacity)
    }

    // MARK: Generate button

    @ViewBuilder
    private var generateButton: some View {
        let canGenerate = store.canGenerate()
        let remaining = store.generationsRemainingToday
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if canGenerate {
                Task { await runGeneration() }
            } else {
                paywallTrigger = .insightsProjection // re-uses Pro pitch; could add .cookLimit
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: canGenerate ? "wand.and.stars" : "lock.fill")
                Text(canGenerate ? "Cook me something" : "Out of free recipes today")
            }
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(SCTheme.Gradients.cta, in: Capsule())
            .shadow(color: SCTheme.Colors.accentPink.opacity(0.32), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(generating)
        if !subs.isPro && remaining < .max {
            Text("\(remaining) of \(RecipeStore.dailyFreeGenerations) free today.")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: Recents rail

    private var recentsRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Skip the very first (rendered as hero above).
                    ForEach(Array(store.recents.dropFirst())) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            RecipeCardSmall(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Saved

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SAVED")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.saved.count)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(store.saved) { recipe in
                NavigationLink {
                    RecipeDetailView(recipe: recipe)
                } label: {
                    SavedRecipeRow(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceFootnote: some View {
        Text("Recipe structure on-device. Nutrition from USDA FoodData Central.")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
    }

    // MARK: Generation

    private func runGeneration() async {
        generating = true
        defer { generating = false }

        if !store.canGenerate() {
            paywallTrigger = .insightsProjection
            return
        }

        let goals = GoalsStore.shared.goals
        let totals = MealDiary.shared.dailyTotals
        let remainingCalories = max(0, Int(goals.calories - totals.calories))
        let remainingProtein = max(0, Int(goals.proteinGrams - totals.proteinGrams))
        let pantryNames = pantry.items.map(\.name)
        let seeds: [String] = useExpiring
            ? (notificationRouter.cookSeedIngredients.isEmpty
                ? pantry.expiringSoon().map(\.name)
                : notificationRouter.cookSeedIngredients)
            : []
        let brief = RecipeGenerator.Brief(
            pantryItems: pantryNames,
            seedIngredients: seeds,
            remainingCalories: hitMacros ? remainingCalories : 700,
            remainingProteinGrams: hitMacros ? remainingProtein : 35,
            maxMinutes: quickOnly ? 20 : nil,
            diet: nil,
            index: store.recents.count,
            recentRecipeNames: Array(store.recents.prefix(6).map(\.name))
        )

        do {
            let raw = try await RecipeGenerator.shared.generate(brief)
            store.recordGeneration()
            // Compute USDA nutrition off the main thread.
            if let usda = try? USDAService() {
                let calc = RecipeNutritionCalculator(usda: usda)
                let priced = await calc.calculate(raw)
                store.record(priced)
            } else {
                store.record(raw)
            }
        } catch {
            generationError = error.localizedDescription
        }
    }
}

// MARK: - Hero banner

private struct HeroBanner: View {
    let recipe: Recipe

    private var topIngredients: [String] {
        recipe.ingredients.prefix(3).map(\.name)
    }

    var body: some View {
        ZStack {
            // Base gradient
            RoundedRectangle(cornerRadius: SCTheme.Radius.lg, style: .continuous)
                .fill(gradient)
                .frame(height: 200)

            // Top sheen
            RoundedRectangle(cornerRadius: SCTheme.Radius.lg, style: .continuous)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top, endPoint: .center
                ))
                .frame(height: 200)
                .blendMode(.softLight)

            // Bottom shade for legibility
            RoundedRectangle(cornerRadius: SCTheme.Radius.lg, style: .continuous)
                .fill(LinearGradient(
                    colors: [.clear, .black.opacity(0.18)],
                    startPoint: .center, endPoint: .bottom
                ))
                .frame(height: 200)

            // Off-center icon (right side, large)
            HStack {
                Spacer()
                Image(systemName: recipe.symbol)
                    .font(.system(size: 88, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: shadowTint.opacity(0.55), radius: 18, y: 6)
                    .padding(.trailing, 24)
                    .rotationEffect(.degrees(-8))
            }
            .frame(height: 200)

            // Ingredient strip (bottom-left)
            VStack {
                Spacer()
                HStack {
                    if topIngredients.isEmpty {
                        EmptyView()
                    } else {
                        HStack(spacing: 6) {
                            ForEach(topIngredients, id: \.self) { name in
                                Text(name)
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.white.opacity(0.22)))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
            .frame(height: 200)
        }
        .shadow(color: shadowTint.opacity(0.32), radius: 16, y: 8)
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
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let icon: String
    @Binding var on: Bool
    let tint: Color
    var disabled: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            on.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(on ? .white : (disabled ? .secondary : .primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(on ? tint : Color.primary.opacity(0.06), in: Capsule())
            .opacity(disabled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Macro pill

private struct MacroPill: View {
    let label: String
    let value: String
    let tint: Color
    let soft: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(tint.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.75)
        )
    }
}

// MARK: - Small recipe card

private struct RecipeCardSmall: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(gradient)
                    .frame(width: 160, height: 90)
                Image(systemName: recipe.symbol)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.92))
            }
            Text(recipe.name)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .heavy))
                Text("\(recipe.totalMinutes)m")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(Int(recipe.perServing.calories)) kcal")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.secondary)
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
}

// MARK: - Saved row

private struct SavedRecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(SCTheme.Colors.accentPink.opacity(0.15))
                Image(systemName: recipe.symbol)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(SCTheme.Colors.accentPink)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(recipe.totalMinutes) min")
                    Text("·")
                    Text("\(Int(recipe.perServing.calories)) kcal/serving")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .scCardStyle()
    }
}

#Preview {
    CookView()
}
