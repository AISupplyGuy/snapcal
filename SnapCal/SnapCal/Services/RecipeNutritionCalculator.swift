import Foundation

// Per ARCHITECTURE.md: the model proposes the recipe; USDA computes the
// numbers. This calculator takes a freshly-generated Recipe (with
// .perServing == .zero) and returns a copy with `perServing` and each
// ingredient's `perServing` populated by hitting USDA per ingredient.
//
// Failure mode: USDA misses are common for compound ingredients ("garlic
// powder", "everything bagel seasoning"). We don't fail the whole
// recipe — missed ingredients contribute zero to the per-serving total
// and stay out of the macro chart, which mirrors how the Track tab
// handles unverifiable items.
//
// Cache: USDAService already caches its responses internally, so we
// don't add a second layer here.
actor RecipeNutritionCalculator {
    private let usda: USDAService

    init(usda: USDAService) {
        self.usda = usda
    }

    func calculate(_ base: Recipe) async -> Recipe {
        var ingredients: [RecipeIngredient] = []
        var totalForRecipe: NutritionFacts = .zero

        for ingredient in base.ingredients {
            let grams = Self.gramsApproximation(quantity: ingredient.quantity, unit: ingredient.unit, name: ingredient.name)
            // Skip "to taste" / unknown-quantity / 0g ingredients without
            // recording an expensive USDA round-trip.
            guard grams > 0 else {
                ingredients.append(ingredient)
                continue
            }
            do {
                let food = try await usda.bestMatch(for: ingredient.name)
                let nutrition = await usda.nutrition(for: food, gramsEstimate: grams)
                var enriched = ingredient
                enriched.perServing = nutrition.scaled(by: 1.0 / Double(max(1, base.servings)))
                ingredients.append(enriched)
                totalForRecipe = totalForRecipe + nutrition
            } catch {
                ingredients.append(ingredient)
            }
        }

        var out = base
        out.ingredients = ingredients
        out.perServing = totalForRecipe.scaled(by: 1.0 / Double(max(1, base.servings)))
        return out
    }

    // Rough quantity → grams converter for the units we let the recipe
    // model emit. Density-based; intentionally simple. Wrong by 20% is
    // fine here — it's still 10× better than a model-hallucinated calorie
    // value, and the error is at the macro-summation level (not surfaced
    // as wrong-by-N% per ingredient).
    static func gramsApproximation(quantity: Double, unit: String, name: String) -> Double {
        let unitLower = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let nameLower = name.lowercased()

        // Direct mass.
        switch unitLower {
        case "g", "gram", "grams": return quantity
        case "kg":                  return quantity * 1000
        case "oz", "ounce", "ounces": return quantity * 28.35
        case "lb", "lbs", "pound", "pounds": return quantity * 453.6
        default: break
        }

        // Volume. Convert to mL first, then approximate by density.
        let mL: Double? = {
            switch unitLower {
            case "ml":    return quantity
            case "l":     return quantity * 1000
            case "tsp":   return quantity * 4.93
            case "tbsp":  return quantity * 14.79
            case "cup":   return quantity * 236.6
            case "fl oz", "floz": return quantity * 29.57
            case "pint":  return quantity * 473.2
            case "quart": return quantity * 946.4
            default:      return nil
            }
        }()
        if let mL {
            // Density g/mL by ingredient family. Defaults to water (1.0).
            let density: Double = {
                if nameLower.contains("oil") || nameLower.contains("butter") { return 0.91 }
                if nameLower.contains("honey") || nameLower.contains("syrup") { return 1.4 }
                if nameLower.contains("flour") { return 0.53 }
                if nameLower.contains("sugar") { return 0.85 }
                if nameLower.contains("rice") || nameLower.contains("oat") { return 0.85 }
                if nameLower.contains("salt") { return 1.2 }
                return 1.0
            }()
            return mL * density
        }

        // Per-piece approximations for common count-based items.
        switch unitLower {
        case "count", "ct", "piece", "pieces", "whole":
            return quantity * Self.pieceWeight(for: nameLower)
        case "clove", "cloves":
            return quantity * 5
        case "slice", "slices":
            return quantity * 25
        case "pinch", "to taste", "to-taste":
            return 0
        default:
            return 0
        }
    }

    private static func pieceWeight(for nameLower: String) -> Double {
        if nameLower.contains("egg") { return 50 }
        if nameLower.contains("apple") { return 180 }
        if nameLower.contains("banana") { return 118 }
        if nameLower.contains("avocado") { return 200 }
        if nameLower.contains("onion") { return 150 }
        if nameLower.contains("tomato") { return 120 }
        if nameLower.contains("potato") { return 170 }
        if nameLower.contains("lemon") || nameLower.contains("lime") { return 65 }
        if nameLower.contains("pepper") { return 120 }
        if nameLower.contains("carrot") { return 60 }
        return 100
    }
}
