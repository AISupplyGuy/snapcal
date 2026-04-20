"""Meal analysis prompt for Gemini 2.5 Flash. Kept standalone so it can be tuned without touching the runner."""

MEAL_ANALYSIS_PROMPT = """Analyze this meal photo and return a JSON object with the following structure. Be specific about portion sizes. If multiple items are visible, list each separately. Use USDA nutritional data as your reference baseline.

{
  "meal_name": "Brief description of the overall meal",
  "items": [
    {
      "name": "Food item name",
      "portion": "Estimated portion (e.g., '6 oz', '1 cup', '2 slices')",
      "calories": number,
      "protein_g": number,
      "carbs_g": number,
      "fat_g": number,
      "fiber_g": number
    }
  ],
  "total_calories": number,
  "total_protein_g": number,
  "total_carbs_g": number,
  "total_fat_g": number,
  "total_fiber_g": number,
  "confidence": number (0.0 to 1.0),
  "notes": "Any relevant notes about preparation method affecting calories (e.g., 'appears pan-fried, oil estimated at ~120 cal')"
}

Rules:
- Account for cooking oils, sauces, and dressings even if not clearly visible
- Estimate conservatively for ambiguous portions
- If confidence is below 0.6, include specific suggestions for what the user should verify
- Return ONLY valid JSON, no markdown formatting
"""
