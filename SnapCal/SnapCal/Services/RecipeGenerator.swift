import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// Turns "what's in your pantry + what you've got left in your macro
// budget today" into a fully-specified Recipe. Per ARCHITECTURE.md this
// is split: the model is asked ONLY for recipe structure (name,
// ingredients with quantities, steps), and nutrition is computed by
// summing USDA per-ingredient values after the fact. The model never
// sees a calorie number, so it can't make one up.
//
// Engine selection at runtime:
//
//   • If FoundationModels is available AND `SystemLanguageModel.default
//     .availability == .available` (Apple Intelligence ready), use the
//     on-device model. Free, instant, private.
//   • Otherwise, fall back to Gemini Flash. Cloud, costs money, slower —
//     used only on devices that can't run Apple Intelligence.
@MainActor
final class RecipeGenerator {
    static let shared = RecipeGenerator()
    private init() {}

    // Inputs to one generation. The user can pass a partial set; the
    // generator fills in defaults from PantryStore + GoalsStore.
    struct Brief {
        var pantryItems: [String]              // pantry display names — empty = open-ended
        var seedIngredients: [String]          // mandatory items the user pinned (eg "Use this expiring chicken")
        var remainingCalories: Int             // budget left today
        var remainingProteinGrams: Int
        var maxMinutes: Int?                   // nil = no constraint
        var diet: String?                      // "high protein", "vegetarian", etc.
        var index: Int                         // 0-based — drives palette + symbol rotation
        var recentRecipeNames: [String] = []   // titles to steer away from — pulled from RecipeStore.recents
    }

    enum Engine: String {
        case foundation
        case gemini
        case unavailable
    }

    var preferredEngine: Engine {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .foundation
            default: break
            }
        }
        #endif
        // Gemini fallback if we have an API key. Otherwise unavailable.
        if (try? GeminiService()) != nil { return .gemini }
        return .unavailable
    }

    enum GenerationError: LocalizedError {
        case unavailable
        case empty
        case parseFailed
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: return "On-device recipe generation isn't available on this device, and the Gemini fallback isn't configured."
            case .empty:       return "We couldn't dream anything up just now. Try again."
            case .parseFailed: return "Recipe came back in a shape we couldn't parse. Try again."
            case .underlying(let m): return m
            }
        }
    }

    // MARK: Entry point

    func generate(_ brief: Brief) async throws -> Recipe {
        switch preferredEngine {
        case .foundation:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return try await generateWithFoundationModels(brief)
            } else {
                return try await generateWithGemini(brief)
            }
            #else
            return try await generateWithGemini(brief)
            #endif
        case .gemini:
            return try await generateWithGemini(brief)
        case .unavailable:
            throw GenerationError.unavailable
        }
    }

    // MARK: Foundation Models path

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateWithFoundationModels(_ brief: Brief) async throws -> Recipe {
        let session = LanguageModelSession(instructions: Instructions(Self.systemInstructions))
        let prompt = Self.buildPrompt(from: brief)
        do {
            let response = try await session.respond(to: prompt, generating: GeneratedRecipe.self)
            let recipe = Self.materialize(generated: response.content, brief: brief, source: "foundation-models")
            return recipe
        } catch {
            throw GenerationError.underlying(error.localizedDescription)
        }
    }

    // The shape we ask the on-device model to fill. @Generable + @Guide
    // makes Foundation Models constrain its output to a parsable struct
    // — no JSON-string parsing, no hallucinated keys. Numbers ONLY for
    // structural fields (servings, minutes, ingredient quantities). Never
    // for nutrition: we compute that from USDA after the fact.
    @available(iOS 26.0, *)
    @Generable
    struct GeneratedRecipe {
        @Guide(description: "Short, evocative recipe title under 7 words.")
        var name: String

        @Guide(description: "One-sentence pitch for why this recipe fits today's macros and pantry.")
        var summary: String

        @Guide(description: "Number of servings the recipe yields.")
        var servings: Int

        @Guide(description: "Active prep minutes before cooking starts.")
        var prepMinutes: Int

        @Guide(description: "Cook time in minutes once you start cooking.")
        var cookMinutes: Int

        @Guide(description: "Difficulty: easy, medium, or hard.")
        var difficulty: String

        @Guide(description: "Ingredients with quantities. Use grams, ounces, tablespoons, teaspoons, or count.")
        var ingredients: [GeneratedIngredient]

        @Guide(description: "Step-by-step instructions, ordered. Each step is one clear action.")
        var steps: [GeneratedStep]
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedIngredient {
        @Guide(description: "USDA-friendly canonical name. Example: 'chicken breast, raw' not 'chicken'.")
        var name: String
        @Guide(description: "What the user sees on the card. Example: 'Chicken breast'.")
        var displayName: String
        @Guide(description: "Numeric quantity for the entire recipe — not per serving.")
        var quantity: Double
        @Guide(description: "Unit: g, oz, tbsp, tsp, cup, ml, count, clove, pinch, to taste.")
        var unit: String
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedStep {
        @Guide(description: "Single-sentence instruction in active voice.")
        var instruction: String
        @Guide(description: "Suggested timer in seconds when relevant; 0 if no timer.")
        var timerSeconds: Int
    }
    #endif

    // MARK: Gemini fallback

    private func generateWithGemini(_ brief: Brief) async throws -> Recipe {
        guard let gemini = try? GeminiService() else { throw GenerationError.unavailable }
        let prompt = Self.buildPrompt(from: brief)
        do {
            let json = try await gemini.generateRecipeJSON(
                systemPrompt: Self.systemInstructions,
                userPrompt: prompt
            )
            guard let data = json.data(using: .utf8) else { throw GenerationError.parseFailed }
            let parsed = try JSONDecoder().decode(GeminiRecipePayload.self, from: data)
            return Self.materialize(generated: parsed, brief: brief, source: "gemini")
        } catch let err as GenerationError {
            throw err
        } catch {
            throw GenerationError.underlying(error.localizedDescription)
        }
    }

    // Lightweight payload mirror so we can share `materialize` across both
    // engines. Field names match GeneratedRecipe so the prompt asks Gemini
    // for the same shape.
    private struct GeminiRecipePayload: Decodable {
        var name: String
        var summary: String
        var servings: Int
        var prepMinutes: Int
        var cookMinutes: Int
        var difficulty: String
        var ingredients: [GeminiIngredient]
        var steps: [GeminiStep]
    }
    private struct GeminiIngredient: Decodable {
        var name: String
        var displayName: String
        var quantity: Double
        var unit: String
    }
    private struct GeminiStep: Decodable {
        var instruction: String
        var timerSeconds: Int?
    }

    // MARK: Prompt scaffolding

    static let systemInstructions = """
    You are SnapCal Cook — a recipe generator that fits the user's pantry and remaining macro budget for the day. \
    Rules:
    1. Prefer ingredients from the user's pantry. List "from pantry" ones first.
    2. Honor any seed ingredients — they MUST appear in the recipe.
    3. Stay under the user's max time when one is given.
    4. Use straightforward weeknight techniques. No specialty equipment unless the user already owns it.
    5. Quantities must be for the whole recipe (not per serving). Use grams or ounces for proteins, tbsp/tsp for fats, cup for liquids, count for whole items.
    6. NEVER include calorie or macro numbers. SnapCal computes nutrition from a verified database after you respond.
    7. Names: keep recipe titles short and concrete; keep ingredient `name` USDA-friendly ("chicken breast, raw"), and `displayName` user-friendly ("Chicken breast").
    8. VARIETY: when "Recently made" is provided, pick a meaningfully different recipe — different protein, different cuisine, or different cooking method. Do not return another stir-fry if a stir-fry is in the list. Do not reuse a title or near-duplicate of any listed name.
    """

    static func buildPrompt(from brief: Brief) -> String {
        var lines: [String] = []
        if !brief.pantryItems.isEmpty {
            lines.append("Pantry items: \(brief.pantryItems.joined(separator: ", ")).")
        }
        if !brief.seedIngredients.isEmpty {
            lines.append("MUST USE: \(brief.seedIngredients.joined(separator: ", ")).")
        }
        lines.append("Remaining today: \(brief.remainingCalories) kcal, \(brief.remainingProteinGrams) g protein.")
        if let m = brief.maxMinutes { lines.append("Max total time: \(m) minutes.") }
        if let d = brief.diet { lines.append("Diet preference: \(d).") }
        if !brief.recentRecipeNames.isEmpty {
            lines.append("Recently made (DO NOT repeat or echo these — pick something distinctly different): \(brief.recentRecipeNames.joined(separator: "; ")).")
        }
        lines.append("Generate one recipe.")
        return lines.joined(separator: "\n")
    }

    // MARK: Materialization (model output → Recipe with USDA nutrition)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func materialize(
        generated: GeneratedRecipe,
        brief: Brief,
        source: String
    ) -> Recipe {
        let pantryLower = Set(brief.pantryItems.map { $0.lowercased() })
        let ingredients = generated.ingredients.map {
            RecipeIngredient(
                name: $0.name,
                displayName: $0.displayName,
                quantity: $0.quantity,
                unit: $0.unit,
                fromPantry: pantryLower.contains($0.displayName.lowercased())
                    || pantryLower.contains($0.name.lowercased())
            )
        }
        let steps = generated.steps.enumerated().map { (i, s) in
            RecipeStep(
                index: i + 1,
                instruction: s.instruction,
                timerSeconds: s.timerSeconds > 0 ? s.timerSeconds : nil
            )
        }
        return assemble(
            name: generated.name,
            summary: generated.summary,
            servings: max(1, generated.servings),
            prep: max(0, generated.prepMinutes),
            cook: max(0, generated.cookMinutes),
            difficulty: parseDifficulty(generated.difficulty),
            ingredients: ingredients,
            steps: steps,
            brief: brief,
            source: source
        )
    }
    #endif

    private static func materialize(
        generated: GeminiRecipePayload,
        brief: Brief,
        source: String
    ) -> Recipe {
        let pantryLower = Set(brief.pantryItems.map { $0.lowercased() })
        let ingredients = generated.ingredients.map {
            RecipeIngredient(
                name: $0.name,
                displayName: $0.displayName,
                quantity: $0.quantity,
                unit: $0.unit,
                fromPantry: pantryLower.contains($0.displayName.lowercased())
                    || pantryLower.contains($0.name.lowercased())
            )
        }
        let steps = generated.steps.enumerated().map { (i, s) in
            RecipeStep(
                index: i + 1,
                instruction: s.instruction,
                timerSeconds: (s.timerSeconds ?? 0) > 0 ? s.timerSeconds : nil
            )
        }
        return assemble(
            name: generated.name,
            summary: generated.summary,
            servings: max(1, generated.servings),
            prep: max(0, generated.prepMinutes),
            cook: max(0, generated.cookMinutes),
            difficulty: parseDifficulty(generated.difficulty),
            ingredients: ingredients,
            steps: steps,
            brief: brief,
            source: source
        )
    }

    private static func assemble(
        name: String,
        summary: String,
        servings: Int,
        prep: Int,
        cook: Int,
        difficulty: RecipeDifficulty,
        ingredients: [RecipeIngredient],
        steps: [RecipeStep],
        brief: RecipeGenerator.Brief,
        source: String
    ) -> Recipe {
        // Per-serving nutrition is computed elsewhere (RecipeNutritionCalculator)
        // so this assembler stays sync. Default to .zero — caller fills in.
        return Recipe(
            id: UUID(),
            name: name,
            summary: summary,
            symbol: pickSymbol(for: ingredients, index: brief.index),
            palette: RecipePalette.auto(for: brief.index),
            servings: servings,
            prepMinutes: prep,
            cookMinutes: cook,
            difficulty: difficulty,
            ingredients: ingredients,
            steps: steps,
            perServing: .zero,
            sourceTag: source,
            createdAt: .now
        )
    }

    private static func parseDifficulty(_ raw: String) -> RecipeDifficulty {
        switch raw.lowercased() {
        case "easy": return .easy
        case "hard", "advanced": return .hard
        default: return .medium
        }
    }

    // Heuristic SF Symbol pick based on dominant ingredient. Keeps the
    // visual identity SnapCal-specific without ever loading a stock photo.
    private static func pickSymbol(for ingredients: [RecipeIngredient], index: Int) -> String {
        let lower = ingredients.map { $0.name.lowercased() + " " + $0.displayName.lowercased() }.joined(separator: " ")
        if lower.contains("egg")     { return "fork.knife.circle.fill" }
        if lower.contains("salmon") || lower.contains("tuna") || lower.contains("fish") { return "fish.fill" }
        if lower.contains("chicken") || lower.contains("turkey") { return "bird.fill" }
        if lower.contains("beef") || lower.contains("steak") { return "flame.fill" }
        if lower.contains("pasta") || lower.contains("noodle") { return "takeoutbag.and.cup.and.straw.fill" }
        if lower.contains("rice") || lower.contains("grain") { return "leaf.fill" }
        if lower.contains("salad") || lower.contains("greens") { return "leaf.circle.fill" }
        if lower.contains("smoothie") || lower.contains("yogurt") { return "cup.and.saucer.fill" }
        let pool = ["fork.knife", "frying.pan.fill", "carrot.fill", "leaf.fill", "flame.fill"]
        return pool[index % pool.count]
    }
}
