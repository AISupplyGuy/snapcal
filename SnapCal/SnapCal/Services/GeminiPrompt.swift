import Foundation

enum GeminiPrompt {
    // Builds the meal-identification prompt at request time. `supportedChains`
    // is the list of chain names currently seeded in the chain_menu_items
    // table (fetched from ChainMenuSource). When a chain is supported, we
    // tell Gemini to collapse the meal into a single menu-item name so the
    // chain lookup can resolve it. When the detected chain is NOT supported,
    // we tell Gemini to decompose normally — proprietary menu names won't
    // match anything in USDA and decomposition gives better calorie accuracy
    // than a bad chain-name lookup.
    static func mealIdentification(supportedChains: [String]) -> String {
        let chainList = supportedChains.isEmpty
            ? "(none currently supported)"
            : supportedChains.map { "'\($0)'" }.joined(separator: ", ")

        let chainRule: String
        if supportedChains.isEmpty {
            chainRule = """
            CHAIN RESTAURANT RULE:
            The backend currently has no chain nutrition databases wired up. \
            Always decompose the meal into its component ingredients, even if \
            you detect a brand cue. Set brand_cue for telemetry when visible, \
            but still return one item per distinguishable ingredient.
            """
        } else {
            chainRule = """
            CHAIN RESTAURANT RULE (very important):
            The backend has verified nutrition data for ONLY these chains: \(chainList).

            If the brand_cue you detect matches one of those supported chains, do NOT decompose the meal into component ingredients. Instead, return a SINGLE item whose name matches the chain's menu item as closely as possible. Examples:
            - Chipotle bowl with chicken, rice, beans, salsa → ONE item named "Chicken Burrito Bowl", NOT seven items.
            - Shake Shack burger with fries → TWO items: "ShackBurger" and "Fries".
            - Starbucks latte with pastry → TWO items: the specific drink name ("Grande Caffe Latte") and the pastry.
            - McDonald's Big Mac combo → TWO or THREE items: "Big Mac", "Large Fries", "Medium Coke".
            The backend looks these up against the chain's actual published nutrition. Decomposing defeats that lookup.

            If the brand_cue you detect is NOT in the supported list above (or brand_cue is null), decompose normally into ingredients. Proprietary menu names for unsupported chains won't resolve in any database, so decomposition gives better accuracy than a useless single-item lookup. Still set brand_cue so we can see which chains users photograph most.
            """
        }

        return """
        Analyze this meal photo. Identify every distinct food item and estimate the portion size for each. Do NOT estimate calories, macros, or nutrition. Those will be computed by the app from a verified database after you respond.

        Return ONLY a valid JSON object, no markdown, with this exact structure:

        {
          "meal_name": "Brief description of the overall meal",
          "items": [
            {
              "name": "Specific food item name suitable for a USDA FoodData Central search (e.g., 'grilled chicken breast, skinless', 'jasmine rice, cooked', 'asparagus, steamed')",
              "portion_amount": number,
              "portion_unit": "EXACTLY ONE of these strings: g, oz, cup, slice, piece, tbsp, tsp, ml. Never use other words (no 'bun', 'patty', 'scoop', 'bottle', 'can'). If the item is countable but doesn't fit those units, use 'piece'.",
              "portion_description": "Human-readable portion (e.g., '6 oz', '1 cup cooked', '2 slices')",
              "preparation": "Cooking method if identifiable (e.g., 'grilled', 'pan-fried in oil', 'steamed', 'raw')",
              "brand_cue": "Name of the restaurant chain or brand IF you see any of: a visible logo, branded cup/bowl/wrapper/bag, branded napkin, distinctive chain-specific packaging, a branded receipt, a menu card in frame, OR if the presentation matches a chain's signature styling. Return just the chain's common name (e.g. 'Chipotle', 'McDonald''s', 'Starbucks'). Set for ANY recognizable chain, not just supported ones — the app uses this for telemetry. Otherwise null.",
              "item_confidence": number (0.0 to 1.0)
            }
          ],
          "plate_context": "home | restaurant | takeout | packaged | unknown",
          "reference_object_present": boolean,
          "overall_confidence": number (0.0 to 1.0),
          "clarifying_questions": ["Short question to ask the user if overall_confidence < 0.6, else empty array"]
        }

        Rules:
        - Name each item so a USDA search for that exact string will find the right food.
        - Include oils, sauces, and dressings as separate items when visible or strongly implied by preparation.
        - When portion is ambiguous, estimate conservatively and drop item_confidence accordingly.
        - Set reference_object_present to true only if a hand, fork, spoon, or plate edge of known size is clearly in frame.
        - Never output calories, protein, carbs, fat, or fiber. Those are computed downstream.

        \(chainRule)
        """
    }
}
