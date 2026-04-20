# SnapCal Week 0: Gemini accuracy de-risk

The entire SnapCal thesis rests on one question: can Gemini 2.5 Flash estimate calories and macros from a meal photo accurately enough to build a consumer product around. This harness answers that before a single line of Swift gets written.

## Kill-criteria

Run at least 20 meals through the harness. If median calorie error exceeds 25%, the product needs a different model, a different prompt, or a rethink. If median error is under 15%, this is a green light. Anything in between means prompt tuning is worth a day.

## Setup

```
cd projects/snapcal/week0-accuracy-test
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Open `.env` and paste a Gemini key from https://aistudio.google.com. Free tier is fine for this test.

## Gathering test data

The quality of the test is the quality of the ground truth. Bad ground truth looks like accuracy problems that don't exist.

Three categories of test meal, aim for 7 each (21 total):

1. **Plain single ingredients.** Grilled chicken breast weighed on a kitchen scale, a banana weighed, a cup of cooked rice measured. USDA values are gospel here.
2. **Packaged foods.** Protein bar, Greek yogurt, frozen burrito. Shoot the food next to its nutrition label (crop label out of the photo Gemini sees — keep it in a separate reference shot).
3. **Restaurant meals with published nutrition.** Chipotle bowls, Sweetgreen, Chick-fil-A. Their nutrition calculators are close enough. Note the exact customizations.

Avoid for v1: homemade casseroles, mixed drinks, anything where you can't verify ground truth within ±5%.

## Running the test

Drop photos in `meals/`. Filenames must match the `filename` column in `ground_truth.csv`. Edit that CSV with real ground truth values. Then:

```
python analyze.py
```

Each meal costs roughly $0.002. 30 meals ≈ 6 cents.

## Reading the output

Console shows median and mean percent error per metric plus the "within ±20%" pass rate. Full per-row results (raw response included) save to `results/run_YYYYMMDD_HHMMSS.csv`.

Calorie accuracy is the one that decides the project. Protein and fiber are secondary. If calories are within 20% but fiber is off by 50%, that is fine — fiber is a rounding error in a consumer app.

## Next steps by outcome

**Green (median calorie err ≤ 15%):** start Week 1, scaffold Xcode project.

**Yellow (15 to 25%):** open `prompt.py`, tune for a day. Try adding few-shot examples, try asking the model to reason about cooking oil and sauces before producing the JSON, try `gemini-2.5-pro` on a subset to see the ceiling.

**Red (> 25%):** test GPT-4o Vision for comparison. If both fail, the consumer pitch changes: AI as first-pass with mandatory confirmation step, not "snap and done."
