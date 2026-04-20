# SnapCal architecture

Technical notes for the SnapCal iOS build. Written 2026-04-19 after the Week 0 Gemini accuracy test surfaced the portion-estimation and hallucinated-calorie problem. Applies the same pattern across both tabs: use the AI model for identification and structure, use verified databases for numbers.

## Meal tracking (Track tab)

**Rule: never ask the model to calculate calories. Ask it to identify the food. Then look up the numbers.**

Gemini 2.5 Flash is accurate at "this plate contains grilled salmon, jasmine rice, and asparagus." It is unreliable at "this plate contains 412 kcal." Week 0 confirmed it. Stock-photo predictions ranged from 0% error (clean single items) to 2300% error (a "California roll" photo showing a full sushi platter). All failures were portion misreads, not identification errors.

The accuracy fix is layered. Each layer compounds.

### Layer 1: RAG against USDA FoodData Central

The Gemini prompt returns structured JSON with item names and portion estimates. A backend function hits the USDA FoodData Central API for each item, multiplies by the model's portion estimate, and sums. The model is never trusted for calorie or macro values. It is trusted only for labels and portion size.

USDA has 400k+ lab-verified foods. Free API. Standard portions defined per food. This single change kills the bulk of the accuracy problem and is the highest-leverage move.

Implementation note: cache USDA responses aggressively. Same foods get eaten thousands of times. The same "grilled chicken breast 6oz" lookup should hit memory, not the network.

### Layer 2: Barcode-first UX

Roughly a third of what users log is packaged: cereal, protein bars, frozen meals, yogurt cups, sports drinks. For packaged food, a barcode scan is an order of magnitude more accurate than any photo analysis. Real-world users report ~95% accuracy on barcode paths in current-generation apps.

Open Food Facts provides a free API with 3M+ barcodes. For barcode-scannable food, the UX skips the camera entirely. The user flow is: open Track tab, see a large "Scan Barcode" option next to the camera button, tap once, done. Photo analysis is only the fallback for unpackaged food.

**Mandatory confirmation step.** The 5% failure mode in competing apps is barcode-to-wrong-product mismatches. Users report scanning a protein bar and getting the wrong flavor entered silently, or getting a completely different brand's product. The fix is non-optional: after every barcode scan, the app shows a confirmation sheet with the product image, name, brand, and serving size before committing the log entry. One tap to confirm, one tap to reject and switch to manual entry. The half-second of friction kills the entire "wrong product logged" complaint class and is a trust win we should not skip.

If Open Food Facts returns multiple entries for the same UPC (which happens with private-label products and international repackaging), show all candidates and let the user pick. Never auto-select.

### Layer 3: Portion calibration

Photo-based portion estimation has a hard ceiling without scale reference. The camera cannot tell a 4oz steak from a 10oz steak. Two moves to break that ceiling.

First: ask the user to include a reference object in the frame. Their hand, a standard fork, the edge of a plate. Gemini can calibrate portion size against a known-scale object. The UX shows a soft overlay prompt: "Include your hand or fork for better accuracy."

Second, on iPhone Pro models with LiDAR: use the depth data to measure actual plate dimensions and derive volume. This is a moat. Cal AI does not do it. MyFitnessPal does not do it. Food photography competitors using standard iPhone cameras cannot match the accuracy of a LiDAR-equipped one.

LiDAR availability check at app launch. Show a small "LiDAR enabled" badge when available. Degrade gracefully to reference-object UX when not.

### Layer 4: User correction flywheel

This is the compounding moat. Every time a user adjusts the portion slider after a Gemini prediction, log a tuple: photo bytes, initial model prediction, user-corrected value, timestamp.

Log it silently. No user-visible feature. No opt-in friction (assuming it is disclosed in privacy policy). Keep data on-device until the user has opted into cloud sync, then route to a private Supabase or private S3 bucket.

In six months of real users, you accumulate 50k+ labeled examples of real food photographed by real iPhones with real portion corrections. That dataset is worth more than any model you could buy. It lets you fine-tune a small on-device Core ML model later that is cheaper, faster, more private, and more accurate than calling Gemini. That is the moat other apps cannot replicate without years of user data.

Start collecting from v1.0 even if the dataset is not used for a year. It is free to collect and impossible to retrofit.

### Layer 5: Confidence-based model tiering

Don't pay Pro-tier compute for a cherry tomato, but don't accept Flash-tier accuracy on a complex restaurant plate. The right signal for "should I escalate to a stronger model" is **Gemini's own confidence score**, not item count, not file size, not photo composition.

**Why confidence beats item count as the signal:**

Item count was considered and rejected as the gating signal, even though the intuition ("simple photo = weaker model, complex photo = stronger model") is directionally right. The problems:

- You need a model to count items, so the cheap first call still costs. On hard photos you end up paying for two model calls (count → re-run).
- Item count doesn't map cleanly to nutrition complexity. A burrito is 1 visible item but 10 ingredients inside. A smoothie is 1 item, 5 components. A stew is 1 item, 8 foods. Meanwhile three visually separated items (grilled chicken, rice, broccoli) is trivial.
- Gemini's `overall_confidence` is already calibrated to actual task difficulty — including these hidden-ingredient cases — so it's strictly better than any proxy.

**The tiered routing:**

| Signal | Action |
|---|---|
| `brand_cue` returned by Gemini | Skip ensemble entirely. Chain menu DB is the truth source. |
| `overall_confidence >= 0.7` | Accept Flash 2.5 response as-is. |
| `overall_confidence < 0.7` | Silently re-send the photo to **Gemini 2.5 Pro**. Compare answers. Agree within 25% → use Flash's answer. Diverge → prompt user to verify. |
| Optional user toggle "Quick mode" | Use Flash-Lite instead of Flash for users who know they're logging one simple thing and want sub-5s response. |

**Why Gemini 2.5 Pro as the fallback (not GPT-4o):**

Same provider, single contract, single monitoring surface, no cross-provider prompt translation. Pro's accuracy advantage over Flash is meaningful on hard cases (multi-component dishes, ambiguous portions, low-light photos) — which is exactly the population we're escalating. GPT-4o would work equally well; not worth adding a second provider relationship for a marginal accuracy delta.

**Cost math at scale:**

- High-confidence cases (estimated ~90% of logs in early dogfooding) stay at Flash pricing — roughly $0.0003/photo.
- Low-confidence escalations (~10%) add one Pro call — roughly $0.015/photo on top.
- Brand-routed cases skip the model entirely for nutrition — free after the initial ID.
- Blended cost per meal analysis settles around $0.001–$0.002. A user logging 5 meals/day costs the business under $0.01/day in model spend, well below any reasonable price point.

Outlier predictions never reach the user unflagged, and the common case stays cheap and fast.

### Summary of Track tab architecture

```
photo → Gemini (labels + portions + confidence + context cues)
                    ↓
     brand detected? → restaurant nutrition API
                    ↓
     else           → USDA FoodData Central lookup
                    ↓
     apply personal portion offset (from user's correction history)
                    ↓
     anomaly check vs user's 30-day baseline
                    ↓
     if confidence low OR anomaly flagged → GPT-4o second opinion
                    ↓
     final numbers → user sees card with slider
                    ↓
     slider movement → log correction → updates user portion model
                                      → feeds global correction DB
```

## Personalization (the real moat)

The five accuracy layers above are table stakes. Any competitor with a decent engineering budget can replicate them. They get you to "accurate meal tracker." The personalization section is what takes SnapCal to "accurate FOR YOU meal tracker," and it is where the compounding defensive moat lives.

Five post-USDA-lookup AI operations do the personalization work. All of them sit on top of the correction flywheel and get better the longer a user uses the app. A cold-start competitor cannot replicate this without matching years of user data.

### Personal portion calibration

A small on-device Core ML model (or a rolling regression) learns per-user portion offsets from the correction flywheel. The system learns, over time: this user's "chicken breast" portions run 15% larger than the USDA standard. This user's "pasta" portions run 20% smaller. The next Gemini prediction for that food gets multiplied by the learned offset before display.

Implementation: after N corrections for a given food (N = 5 minimum), compute a rolling mean of the user's correction ratio. Apply it on-device to future predictions for the same food. After three months of consistent use, portion accuracy converges on the user's actual eating habits regardless of what USDA says is standard.

### Brand and restaurant routing

USDA "cheeseburger" is a generic. A Big Mac and a Five Guys burger both match that category but have materially different calories and macros. An AI classifier looks at visual cues in the photo (logo on the wrapper, distinctive bun or fries, branded packaging, restaurant interior visible in the background) and routes to the specific restaurant's published nutrition when a brand is detected.

Implementation: maintain a database of chain-restaurant nutrition pulled from official APIs or scraped menus (McDonald's, Chipotle, Starbucks, Chick-fil-A, Sweetgreen, Cava, Panera, Subway, Taco Bell, etc.). A secondary Gemini call (or a small classifier) identifies brand cues. If a brand is detected with high confidence, skip USDA and use the restaurant's published values. High-volume users eat at chains often. This unlocks meaningful accuracy beyond what generic USDA categories can provide.

### Context inference

Same food, different reality depending on context. A home-plated chicken breast is typically 5 to 6 ounces. A restaurant-plated chicken breast is typically 8 to 10 ounces. Pasta bowls run smaller at home than in restaurants. Plate type, lighting, surrounding objects, and time of day are all signals that refine portion estimates beyond what the food itself tells the model.

Implementation: add a context-classification step to the Gemini prompt. Ask the model explicitly for plate_type (home, restaurant, takeout) and likely_portion_modifier (small, standard, large). Combine with the device's time of day (breakfast, lunch, dinner, snack), since meal-time patterns predict portion size statistically.

### Cross-meal anomaly detection

Every user has a baseline daily calorie pattern. Most people eat within ±20% of their average on normal days. When a new prediction deviates wildly from the user's own history, the system prompts for verification instead of silently logging. "You normally eat 500 kcal at lunch. This says 1,200. Want to verify?" This is safety-net AI. It catches the obvious cases where Gemini misreads a portion.

Implementation: maintain a 30-day rolling window of the user's meal-by-time-of-day averages. When a prediction comes in, compute the z-score against the user's own history for that meal slot. If z > 2 (more than two standard deviations above the user's norm), prompt for verification before logging. Log the verification decision as an additional training signal.

### Temporal freshness

USDA's database is static. It updates slowly. Restaurants reformulate menus constantly. New products launch every week. Seasonal produce varies in size, sugar content, and water content. The correction flywheel, when aggregated across the full user base, keeps SnapCal current in ways USDA alone cannot.

Implementation: aggregate anonymized corrections across all users. When a specific food's mean correction ratio drifts meaningfully over a 30-day window, flag it for review and update the effective database value server-side. This is how SnapCal gets BETTER than USDA over time, not just as accurate. The user base becomes a continuously-sampled nutrition update loop.

### Why this is the actual moat

Five accuracy layers can be built by any serious engineering team. They are necessary but not sufficient. The personalization section requires real user data at scale to work. A cold-start SnapCal clone has none of it. The dataset accumulated in the first six months of real users becomes the defensible asset. Competitors without it will feel generic by comparison even if their underlying accuracy stack is technically identical.

## Weekly rolling redistribution (retention mechanic)

Daily calorie targets are the industry default. They are also the primary reason people quit tracking apps. One bad day (a birthday, a dinner out, a vacation flight) blows the daily number, the user feels defeated, they skip the next day, they stop opening the app. The data is clear: daily targets create a binary pass/fail psychology that is hostile to long-term adherence.

Weekly rolling redistribution flips that. The target is not per-day. It is per-trailing-7-days. Today's implicit calorie budget is derived by taking the user's weekly total goal, subtracting the calories logged on each of the prior six days, and dividing the remainder by one. A big Saturday dinner does not doom Sunday. It just means Sunday's implicit budget is a little lower. Bodies don't care about calendar boundaries anyway. Metabolism averages across days.

Competing apps either don't offer this or offer it as a rigid Monday-to-Sunday weekly mode (MyFitnessPal) that still creates an artificial reset every week. Rolling is better because every day adjusts continuously against the prior six.

### Implementation

The core math is trivial. Daily budget = (weekly_target - sum(last_6_days_logged)) / 1. Or more generally, for a configurable window N: budget = (N * daily_target - sum(last_N-1_days_logged)) / 1.

UX additions needed:
- A "rolling 7-day" toggle in Profile. Default to daily for new users (familiar). Prompt to switch after 7 days of use with a brief explainer.
- The Track tab shows today's dynamic budget at the top, with a secondary line: "7-day pace: on track / +340 cal / -180 cal."
- The weekly shareable report card already makes sense as a 7-day aggregate. Reinforces the rolling mental model.
- A "lock this day" action that freezes the current day's logged value and explicitly redistributes remaining weekly calories across the remaining days. Useful for users who want to be deliberate about a planned indulgence.
- Apply the same redistribution logic to protein independently. Fat and carbs can track daily since they matter less for long-term outcomes.

### Why this is behavioral moat

Retention in nutrition apps is driven by whether the app makes users feel competent or incompetent. Daily targets fail most days. Rolling targets succeed most days. Users who feel competent keep logging. Users who keep logging generate correction data. Correction data is the accuracy moat. Retention compounds into defensibility.

This is a small code change with a large downstream consequence. Build it into v1.

## Recipe generation (Cook tab)

Same pattern. Model for structure, database for numbers.

**Rule: never ask the model to calculate recipe nutrition. Ask it to propose the recipe. Then compute nutrition by summing verified ingredient data.**

Foundation Models (on-device, iOS 18+) receives the pantry inventory as context and generates recipe candidates. The prompt asks only for:

- Recipe name
- Ingredient list with quantities
- Step-by-step instructions
- Cook time
- Servings

It is never asked for calories or macros. Those are computed by the app after the model responds.

The calculation loop: for each ingredient in the generated recipe, the app does a USDA FoodData Central lookup (cached aggressively), multiplies by the ingredient quantity from the recipe, sums across ingredients, and divides by servings. The result is per-serving nutrition that is as accurate as USDA data allows.

This approach has three benefits beyond accuracy.

First, the recipe's nutrition numbers match the user's logged meal nutrition exactly, because both sides use the same USDA source. When a user taps "I made this" and the meal logs automatically, the calorie number on the Track tab card matches what the Cook tab promised. No discrepancy between recipe-time estimate and log-time estimate.

Second, pantry items entered via barcode scan already have Open Food Facts nutrition attached. When a recipe uses one of those items, the app prefers the actual product the user has over the generic USDA value. Recipes become more accurate because the ingredient data is closer to what is actually being cooked.

Third, the on-device model can use cheaper/smaller variants (Foundation Models on iPhone 15 Pro is small) because the numerical precision work is offloaded. The model only has to be good at creative recipe structure, not at numerical recall.

### Expiration date estimation

Same pattern applies to receipt OCR expiration estimation. The Vision framework performs OCR on a grocery receipt. The app asks Gemini (or a small local classifier) to categorize each line item into a food type: produce, dairy, protein, packaged dry goods, frozen, etc. The actual expiration window comes from a static lookup table, not the model.

Example: Gemini says "chicken breast, raw, refrigerated" for the line item `CHKN BRST 2LB`. A static lookup table says raw refrigerated poultry is 1-2 days. The app sets the expiration to 2 days from receipt date. The model never has to know "how long does chicken last" because it is in a table.

This lets the expiration windows improve over time independent of the model. Food safety data is a known problem with authoritative sources (USDA, FSIS guidelines). Bake those guidelines into the app. Do not trust the model.

## Shared principles

Three patterns recur across every AI-touching surface in SnapCal.

**Model for identification, database for values.** Applied to Track (Gemini + USDA), Cook (Foundation Models + USDA), Pantry (receipt OCR + static shelf-life table).

**User corrections are the product.** Every slider adjustment, every recipe override, every pantry edit is a labeled training point. Log everything silently from day one. The dataset compounds.

**Cache aggressively.** Users eat the same 50 foods over and over. USDA lookups for "2% milk 1 cup" should happen once ever. Gemini responses for a known barcode should never happen. Both Gemini calls and USDA calls are cached at both device and backend levels.

## What this means for Week 1

Week 1 scope was "camera → Gemini → meal card core loop." That scope still holds, but with one addition: the meal card pipeline must include the USDA lookup step before displaying numbers. Do not ship Week 1 with raw Gemini calorie values on the card. It is a small addition, maybe half a day, and it is the difference between a demo that works occasionally and a foundation that can scale.

Build the correction-logging silently in Week 1 too. No UI, just a Core Data table that records every slider movement with the photo reference and both the original and corrected values. Low cost, high future value.
