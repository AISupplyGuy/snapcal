import SwiftUI

struct MealCardView: View {
    @State var meal: MealEntry
    let photo: UIImage?
    let onCommit: (MealEntry) -> Void
    let onDietaryVariantChange: (MealItem, DietaryVariantPreference, PlateContext) async -> NutritionMatch?
    let onSizeVariantChange: (MealItem, String, PlateContext) async -> NutritionMatch?
    let onLoadChains: () async -> [Chain]
    let onChainReapply: (MealItem, String, PlateContext) async -> NutritionMatch?
    let pristineItemsProvider: () -> [MealItem]?

    @State private var availableChains: [Chain] = []
    @State private var activeChain: Chain?
    @State private var isChainApplying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photoBlock
                headerBlock
                chainPickerBlock
                if meal.needsVerification {
                    verificationBanner
                }
                totalsCard
                itemsList
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        // Pinned Save CTA. Inline at the end of the ScrollView, the button
        // shared the tab-bar's pink/orange gradient and visually merged
        // with it. Pinned + on a backdrop, it's always reachable and
        // unmistakable above the floating bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(
                    Rectangle()
                        .fill(.background)
                        .ignoresSafeArea(edges: .bottom)
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(height: 0.5)
                }
        }
        .task {
            if availableChains.isEmpty {
                availableChains = await onLoadChains()
            }
            activeChain = inferInitialChain()
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

    // "From" picker — lets the user declare the meal's source when the photo
    // has no brand cue (plain pazookie on a plate → BJ's). Selecting a chain
    // re-runs each item through the chain menu lookup.

    private var chainPickerBlock: some View {
        HStack(spacing: 10) {
            Text("From")
                .font(SCTheme.Type_.kicker())
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Menu {
                Button {
                    guard activeChain != nil else { return }
                    applyChainReset()
                } label: {
                    Label("Home / kitchen", systemImage: "house.fill")
                }
                if !availableChains.isEmpty {
                    Divider()
                    ForEach(availableChains) { chain in
                        Button {
                            guard activeChain?.id != chain.id else { return }
                            applyChain(chain)
                        } label: {
                            if activeChain?.id == chain.id {
                                Label(chain.name, systemImage: "checkmark")
                            } else {
                                Text(chain.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: activeChain == nil ? "house.fill" : "storefront.fill")
                        .font(.system(size: 12, weight: .heavy))
                    Text(activeChain?.name ?? "Home")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                    if isChainApplying {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .heavy))
                    }
                }
                .foregroundStyle(activeChain == nil ? .secondary : SCTheme.Colors.accentPink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        (activeChain == nil ? Color.secondary : SCTheme.Colors.accentPink)
                            .opacity(0.12)
                    )
                )
            }
            .disabled(isChainApplying)
            Spacer()
        }
    }

    // Surfaced when the pipeline flagged this meal via Layer 5 — Flash and
    // Pro disagreed by >25% on calories. Numbers are shown in good faith but
    // with a visible caveat so the user slides to double-check before saving.
    private var verificationBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(SCTheme.Colors.accentOrange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Double-check these numbers")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text("The photo was ambiguous, so Flash and Pro landed on different totals. Slide portions below to the amount that feels right before saving.")
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

    private func inferInitialChain() -> Chain? {
        guard let firstSource = meal.items.first(where: { ($0.matchedSourceId ?? "usda") != "usda" })?.matchedSourceId
        else { return nil }
        return availableChains.first { $0.slug == firstSource }
    }

    private func applyChain(_ chain: Chain) {
        isChainApplying = true
        activeChain = chain
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            var updated = meal.items
            for index in updated.indices {
                guard let match = await onChainReapply(updated[index], chain.name, meal.plateContext)
                else { continue }
                updated[index] = apply(match: match, to: updated[index])
            }
            await MainActor.run {
                meal.items = updated
                meal.recomputeTotals()
                isChainApplying = false
            }
        }
    }

    private func applyChainReset() {
        isChainApplying = true
        activeChain = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let restored = pristineItemsProvider() ?? meal.items
            await MainActor.run {
                meal.items = restored
                meal.recomputeTotals()
                isChainApplying = false
            }
        }
    }

    private func apply(match: NutritionMatch, to item: MealItem) -> MealItem {
        var copy = item
        let baselinePer100g: NutritionFacts = copy.gramsEstimate > 0
            ? match.nutrition.scaled(by: 100.0 / copy.gramsEstimate)
            : match.nutrition
        copy.usdaFdcId = {
            guard match.sourceId == "usda",
                  let ext = match.externalId, let id = Int(ext) else { return nil }
            return id
        }()
        copy.usdaDescription = match.displayName
        copy.matchedSourceId = match.sourceId
        copy.matchConfidence = match.confidence
        copy.nutrition = match.nutrition
        copy.baselinePer100g = baselinePer100g
        copy.availableSizeOptions = match.sizeOptions
        copy.selectedSizeKey = match.selectedSizeKey
        return copy
    }

    // MARK: Totals card
    //
    // Derive totals from items on every render so the slider updates feel live.
    // `meal.totals` is still kept in sync at commit time for the persisted copy.

    private var liveTotals: NutritionFacts {
        meal.items.map(\.nutrition).reduce(.zero, +)
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total calories")
                        .font(SCTheme.Type_.kicker())
                        .tracking(1.0)
                        .foregroundStyle(SCTheme.Colors.accentOrange)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(liveTotals.calories))")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(SCTheme.Gradients.heroText)
                            .contentTransition(.numericText(value: liveTotals.calories))
                            .animation(.easeOut(duration: 0.15), value: liveTotals.calories)
                        Text("kcal")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ConfidenceBadge(confidence: meal.overallConfidence)
            }

            HStack(spacing: 10) {
                SCMacroChip(
                    label: "Protein",
                    value: "\(Int(liveTotals.proteinGrams))g",
                    tint: SCTheme.Colors.proteinBlue,
                    softBg: SCTheme.Colors.proteinSoft
                )
                SCMacroChip(
                    label: "Carbs",
                    value: "\(Int(liveTotals.carbGrams))g",
                    tint: SCTheme.Colors.carbGreen,
                    softBg: SCTheme.Colors.carbSoft
                )
                SCMacroChip(
                    label: "Fat",
                    value: "\(Int(liveTotals.fatGrams))g",
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
                ItemRow(
                    item: $item,
                    plateContext: meal.plateContext,
                    onDietaryVariantChange: onDietaryVariantChange,
                    onSizeVariantChange: onSizeVariantChange
                )
            }
        }
    }

    // MARK: Save
    //
    // Items are already live-scaled from baselinePer100g as the user drags.
    // Save just sync's the stored `totals` and hands the meal up for persistence.

    private var saveButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            meal.recomputeTotals()
            onCommit(meal)
        } label: {
            Label("Save meal", systemImage: "checkmark.circle.fill")
                .scCTAStyle()
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - Item row

private struct ItemRow: View {
    @Binding var item: MealItem
    let plateContext: PlateContext
    let onDietaryVariantChange: (MealItem, DietaryVariantPreference, PlateContext) async -> NutritionMatch?
    let onSizeVariantChange: (MealItem, String, PlateContext) async -> NutritionMatch?
    @State private var isVariantLoading = false
    @State private var isGlutenFreeSelected = false
    @State private var selectedSizeKey: String?

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

            if showsGlutenVariantControl {
                Button {
                    if isVariantLoading { return }
                    isGlutenFreeSelected.toggle()
                    let preference: DietaryVariantPreference = isGlutenFreeSelected ? .glutenFree : .notGlutenFree
                    item.dietaryVariantPreference = preference
                    saveVariantPreference(preference)
                    Task {
                        await applyDietaryVariant(preference)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isGlutenFreeSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isGlutenFreeSelected ? SCTheme.Colors.carbGreen : .secondary)
                        Text("Gluten free")
                            .font(SCTheme.Type_.caption())
                            .foregroundStyle(.secondary)
                        if isVariantLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if !sizeOptions.isEmpty {
                HStack(spacing: 8) {
                    Text("Size")
                        .font(SCTheme.Type_.caption())
                        .foregroundStyle(.secondary)
                    ForEach(sizeOptions, id: \.key) { option in
                        Button {
                            if isVariantLoading { return }
                            selectedSizeKey = option.key
                            saveSizePreference(option.key)
                            Task {
                                await applySizeVariant(option.key)
                            }
                        } label: {
                            Text(option.label)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(selectedSizeKey == option.key ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(
                                        selectedSizeKey == option.key
                                        ? SCTheme.Colors.accentPink
                                        : SCTheme.Colors.accentPink.opacity(0.14)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    if isVariantLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
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
                    .onChange(of: item.gramsEstimate) { _, newGrams in
                        item.nutrition = item.baselinePer100g.scaled(by: newGrams / 100.0)
                    }
            }
        }
        .padding(16)
        .scCardStyle()
        .onAppear {
            guard showsGlutenVariantControl else { return }
            let pref = item.dietaryVariantPreference ?? savedVariantPreference
            item.dietaryVariantPreference = pref
            isGlutenFreeSelected = (pref == .glutenFree)
        }
        .onAppear {
            guard !sizeOptions.isEmpty else { return }
            let availableKeys = Set(sizeOptions.map(\.key))
            let pref = savedSizePreference
                .flatMap { availableKeys.contains($0) ? $0 : nil }
                ?? item.selectedSizeKey
                ?? sizeOptions.first?.key
            selectedSizeKey = pref
        }
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

    private var showsGlutenVariantControl: Bool {
        guard item.matchedSourceId == "bjs" else { return false }
        let combined = "\(item.name) \(item.usdaDescription ?? "")".lowercased()
        return combined.contains("pizookie")
    }

    private var sizeOptions: [ChainSizeOption] {
        item.availableSizeOptions ?? []
    }

    private var savedVariantPreference: DietaryVariantPreference {
        guard let raw = UserDefaults.standard.string(forKey: variantDefaultsKey),
              let pref = DietaryVariantPreference(rawValue: raw) else {
            return .notGlutenFree
        }
        return pref
    }

    private var variantDefaultsKey: String {
        "dietaryVariant.bjs.pizookie"
    }

    private var sizeDefaultsKey: String? {
        ChainVariantSupport.preferenceKey(for: item)
    }

    private func saveVariantPreference(_ preference: DietaryVariantPreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: variantDefaultsKey)
    }

    private var savedSizePreference: String? {
        guard let key = sizeDefaultsKey else { return nil }
        return UserDefaults.standard.string(forKey: key)
    }

    private func saveSizePreference(_ sizeKey: String) {
        guard let key = sizeDefaultsKey else { return }
        UserDefaults.standard.set(sizeKey, forKey: key)
    }

    @MainActor
    private func applyDietaryVariant(_ preference: DietaryVariantPreference) async {
        guard preference != .unknown else { return }
        if isVariantLoading { return }
        isVariantLoading = true
        defer { isVariantLoading = false }

        guard let match = await onDietaryVariantChange(item, preference, plateContext) else { return }
        let baselinePer100g: NutritionFacts = item.gramsEstimate > 0
            ? match.nutrition.scaled(by: 100.0 / item.gramsEstimate)
            : match.nutrition

        item.usdaFdcId = {
            guard match.sourceId == "usda",
                  let ext = match.externalId, let id = Int(ext) else { return nil }
            return id
        }()
        item.usdaDescription = match.displayName
        item.matchedSourceId = match.sourceId
        item.matchConfidence = match.confidence
        item.nutrition = match.nutrition
        item.baselinePer100g = baselinePer100g
        item.availableSizeOptions = match.sizeOptions
        item.selectedSizeKey = match.selectedSizeKey
    }

    @MainActor
    private func applySizeVariant(_ sizeKey: String) async {
        if isVariantLoading { return }
        isVariantLoading = true
        defer { isVariantLoading = false }

        guard let match = await onSizeVariantChange(item, sizeKey, plateContext) else { return }
        let baselinePer100g: NutritionFacts = item.gramsEstimate > 0
            ? match.nutrition.scaled(by: 100.0 / item.gramsEstimate)
            : match.nutrition

        item.usdaFdcId = {
            guard match.sourceId == "usda",
                  let ext = match.externalId, let id = Int(ext) else { return nil }
            return id
        }()
        item.usdaDescription = match.displayName
        item.matchedSourceId = match.sourceId
        item.matchConfidence = match.confidence
        item.nutrition = match.nutrition
        item.baselinePer100g = baselinePer100g
        item.availableSizeOptions = match.sizeOptions
        item.selectedSizeKey = match.selectedSizeKey
        selectedSizeKey = match.selectedSizeKey ?? sizeKey
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
