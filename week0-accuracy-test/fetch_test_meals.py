"""
Downloads a curated set of meal photos from Unsplash and writes matching
ground-truth rows to ground_truth.csv.

The ground truth is derived from USDA FoodData Central standard portions
and published restaurant nutrition. It's approximate — the photo may
show a slightly different portion than assumed — so treat results from
this dataset as a DIRECTIONAL signal, not a rigorous accuracy number.

For the rigorous version, replace these rows with your own weighed
photos and measured ground truth.
"""

from __future__ import annotations

import csv
import pathlib
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).parent
MEALS_DIR = ROOT / "meals"
GT_CSV = ROOT / "ground_truth.csv"

# (filename, unsplash_photo_id, meal_name, calories, protein_g, carbs_g, fat_g, fiber_g, notes)
CANDIDATES = [
    ("banana.jpg", "1528825871115-3581a5387919",
     "1 medium banana (~118g)", 105, 1.3, 27, 0.4, 3.1,
     "USDA cavendish medium"),
    ("apple.jpg", "1568702846914-96b305d2aaeb",
     "1 medium apple (~182g)", 95, 0.5, 25, 0.3, 4.4,
     "USDA raw with skin"),
    ("avocado_toast.jpg", "1588137378633-dea1336ce1e2",
     "Avocado toast: 1 slice sourdough + 1/2 avocado",
     280, 7, 28, 15, 7, "Common cafe portion"),
    ("oatmeal_berries.jpg", "1517093157656-b9eccef91cb1",
     "Oatmeal 1 cup cooked + 1/2 cup mixed berries",
     220, 7, 40, 4, 7, "USDA rolled oats + berries"),
    ("greek_yogurt_parfait.jpg", "1488477181946-6428a0291777",
     "Greek yogurt parfait: 1 cup nonfat + granola + berries",
     290, 18, 45, 6, 4, "Common breakfast portion"),
    ("pancakes_stack.jpg", "1567620905732-2d1ec7ab7445",
     "3 buttermilk pancakes + syrup + butter",
     520, 10, 75, 18, 2, "IHOP-style stack"),
    ("scrambled_eggs.jpg", "1572441713132-51c75654db73",
     "2 scrambled eggs cooked in butter",
     220, 13, 1, 18, 0, "USDA large eggs"),
    ("cheeseburger.jpg", "1568901346375-23c9450c58cd",
     "Single patty cheeseburger (fast-food size)",
     300, 15, 33, 12, 2, "McDonald's cheeseburger published nutrition"),
    ("pizza_slice.jpg", "1513104890138-7c749659a591",
     "1 slice NY-style cheese pizza",
     285, 12, 36, 10, 2, "Standard 1/8 of 14-inch pie"),
    ("caesar_salad.jpg", "1546793665-c74683f339c1",
     "Chicken caesar salad, restaurant portion",
     470, 40, 18, 26, 4, "Typical chain restaurant chicken caesar"),
    ("burrito_bowl.jpg", "1546069901-ba9599a7e63c",
     "Chipotle-style chicken burrito bowl: rice, beans, salsa",
     665, 45, 78, 21, 13, "Chipotle published nutrition calculator"),
    ("sushi_roll.jpg", "1553621042-f6e147245754",
     "California roll, 8 pieces",
     320, 9, 47, 11, 3, "Standard sushi restaurant roll"),
    ("ramen_bowl.jpg", "1569718212165-3a8278d5f624",
     "Tonkotsu ramen bowl with chashu and egg",
     600, 22, 65, 28, 4, "Restaurant portion"),
    ("grilled_chicken_breast.jpg", "1604503468506-a8da13d82791",
     "6oz grilled chicken breast, plain",
     280, 53, 0, 6, 0, "USDA boneless skinless, cooked"),
    ("salmon_rice.jpg", "1467003909585-2f8a72700288",
     "6oz grilled salmon + 1 cup rice + vegetables",
     560, 42, 50, 18, 5, "Home dinner plate"),
    ("protein_shake.jpg", "1610970881699-44a5587cabec",
     "Protein shake: 1 scoop whey + banana + 1 cup milk",
     280, 28, 38, 3, 3, "Standard post-workout shake"),
    ("pbj_sandwich.jpg", "1528735602780-2552fd46c7af",
     "PB&J: 2 slices white bread + 2 tbsp PB + 1 tbsp jam",
     380, 12, 50, 15, 4, "USDA standard"),
    ("french_fries.jpg", "1573080496219-bb080dd4f877",
     "Medium french fries (fast food)",
     365, 4, 48, 17, 4, "McDonald's medium published"),
    ("latte.jpg", "1461023058943-07fcbe16d735",
     "Grande 2% caffe latte",
     190, 13, 19, 7, 0, "Starbucks published"),
    ("donut_glazed.jpg", "1551024601-bec78aea704b",
     "1 glazed donut",
     260, 4, 31, 14, 1, "Dunkin glazed published"),
    ("hot_dog.jpg", "1612392062631-94d4fbba9a37",
     "1 hot dog in bun with mustard",
     290, 10, 24, 17, 1, "Ballpark/standard"),
    ("steak_dinner.jpg", "1546964124-0cce460f38ef",
     "8oz sirloin steak + mashed potatoes + vegetables",
     680, 55, 35, 35, 5, "Steakhouse home portion"),
    ("chicken_wings.jpg", "1608039755401-742074f0548d",
     "6 buffalo chicken wings + ranch",
     580, 35, 12, 42, 1, "Wing restaurant serving"),
    ("veggie_salad.jpg", "1512621776951-a57141f2eefd",
     "Mixed vegetable salad + vinaigrette",
     180, 4, 15, 12, 5, "Side salad with dressing"),
    ("muffin_blueberry.jpg", "1607958996333-41aef7caefaa",
     "1 large blueberry muffin (bakery size)",
     460, 6, 61, 22, 2, "Starbucks blueberry muffin published"),
]

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)


def download(photo_id: str, dest: pathlib.Path) -> bool:
    url = f"https://images.unsplash.com/photo-{photo_id}?auto=format&fit=crop&w=1024&h=1024&q=85"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            if resp.status != 200:
                return False
            data = resp.read()
            if len(data) < 5_000:
                return False
            dest.write_bytes(data)
            return True
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
        print(f"    fail: {exc}")
        return False


def main() -> int:
    MEALS_DIR.mkdir(exist_ok=True)

    rows = [
        ("filename", "meal_name", "calories", "protein_g",
         "carbs_g", "fat_g", "fiber_g", "notes")
    ]
    ok = 0
    fail: list[str] = []

    for i, (fn, photo_id, name, cal, p, c, f, fi, notes) in enumerate(CANDIDATES, 1):
        dest = MEALS_DIR / fn
        print(f"[{i:2d}/{len(CANDIDATES)}] {fn} ... ", end="", flush=True)

        if dest.exists() and dest.stat().st_size > 5_000:
            print("cached")
            rows.append((fn, name, cal, p, c, f, fi, notes))
            ok += 1
            continue

        if download(photo_id, dest):
            print(f"ok ({dest.stat().st_size // 1024}kb)")
            rows.append((fn, name, cal, p, c, f, fi, notes))
            ok += 1
        else:
            print("SKIP")
            fail.append(fn)
        time.sleep(0.25)

    with GT_CSV.open("w", newline="") as csv_out:
        writer = csv.writer(csv_out)
        writer.writerows(rows)

    print(f"\n{'=' * 50}")
    print(f"Downloaded {ok}/{len(CANDIDATES)} meals")
    print(f"Ground truth written: {GT_CSV}")
    if fail:
        print(f"Failed (removed from CSV): {', '.join(fail)}")
    print(f"\nNext: python analyze.py")
    return 0 if ok >= 15 else 1


if __name__ == "__main__":
    sys.exit(main())
