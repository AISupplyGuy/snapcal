import Foundation

enum GeminiPrompt {
    static let mealIdentification = """
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
          "brand_cue": "Name of the restaurant chain or brand IF you see any of: a visible logo, branded cup/bowl/wrapper/bag, branded napkin, distinctive chain-specific packaging, a branded receipt, a menu card in frame, OR if the presentation matches a chain's signature styling (Chipotle foil-wrapped burrito in branded bowl, Shake Shack burger in kraft-paper tray with their logo, Starbucks cup, McDonald's red box, Panera ceramic bowl, BJ's pizookie in skillet, Chicago Fire deep-dish pan). Return just the chain's common name like 'Chipotle', 'McDonald''s', 'Starbucks', 'Shake Shack', 'Wendy''s', 'Panera', 'Chicago Fire', 'BJ''s'. Otherwise null.",
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

    CHAIN RESTAURANT RULE (very important):
    If you detect a brand_cue (Chipotle, Shake Shack, Starbucks, McDonald's, Wendy's, Panera, BJ's, Chicago Fire, or any recognizable chain), do NOT decompose the meal into its component ingredients. Instead, return a SINGLE item whose name matches the chain's menu item as closely as possible. Examples:
    - Chipotle bowl with chicken, rice, beans, salsa → ONE item named "Chicken Burrito Bowl", NOT seven items.
    - Shake Shack burger with fries → TWO items: "ShackBurger" and "Fries" (the fries are a separate menu line).
    - Starbucks latte with pastry → TWO items: the specific drink name ("Grande Caffe Latte") and the pastry.
    - McDonald's Big Mac combo → TWO or THREE items: "Big Mac", "Large Fries", "Medium Coke".
    The backend will look these up against the chain's actual published nutrition. Decomposing defeats that lookup. Always prefer one menu-item name over many raw ingredients when brand_cue is set.

    If brand_cue is null (home cooking, generic plate), decompose normally into ingredients as above.
    """
}
