"""
Week 0 accuracy harness for SnapCal.

Feeds meal photos from ./meals/ into Gemini 2.5 Flash using the production prompt,
compares results to ground_truth.csv, and reports per-metric accuracy.

Usage:
    pip install -r requirements.txt
    cp .env.example .env  # then paste your Gemini key
    python analyze.py

Kill-criteria: if median calorie error across 20+ meals exceeds 25%, the core
thesis (AI photo analysis accurate enough to build on) has a hole.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from google import genai
from google.genai import types

from prompt import MEAL_ANALYSIS_PROMPT

ROOT = Path(__file__).parent
MEALS_DIR = ROOT / "meals"
RESULTS_DIR = ROOT / "results"
GROUND_TRUTH_CSV = ROOT / "ground_truth.csv"

METRICS = ["calories", "protein_g", "carbs_g", "fat_g", "fiber_g"]


@dataclass
class Row:
    filename: str
    meal_name: str
    truth: dict
    predicted: dict | None
    raw_response: str
    error: str | None
    latency_ms: int
    confidence: float | None


def load_env() -> tuple[str, str]:
    load_dotenv(ROOT / ".env")
    key = os.getenv("GEMINI_API_KEY", "").strip()
    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash").strip()
    if not key or key.startswith("your_key"):
        sys.exit("GEMINI_API_KEY missing. Copy .env.example to .env and paste your key.")
    return key, model


def load_ground_truth() -> pd.DataFrame:
    if not GROUND_TRUTH_CSV.exists():
        sys.exit(f"ground_truth.csv not found at {GROUND_TRUTH_CSV}")
    df = pd.read_csv(GROUND_TRUTH_CSV)
    missing_cols = {"filename", "meal_name", *METRICS} - set(df.columns)
    if missing_cols:
        sys.exit(f"ground_truth.csv missing required columns: {missing_cols}")
    return df


def parse_json_response(text: str) -> dict | None:
    """Strip markdown fences if present, then parse."""
    cleaned = text.strip()
    fence = re.match(r"^```(?:json)?\s*(.*?)\s*```$", cleaned, re.DOTALL)
    if fence:
        cleaned = fence.group(1)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        return None


def analyze_photo(client: genai.Client, model: str, photo_path: Path) -> tuple[dict | None, str, int]:
    """Returns (parsed_json_or_none, raw_response_text, latency_ms)."""
    image_bytes = photo_path.read_bytes()
    mime = "image/jpeg" if photo_path.suffix.lower() in {".jpg", ".jpeg"} else "image/png"

    start = time.perf_counter()
    response = client.models.generate_content(
        model=model,
        contents=[
            types.Part.from_bytes(data=image_bytes, mime_type=mime),
            MEAL_ANALYSIS_PROMPT,
        ],
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            temperature=0.2,
        ),
    )
    latency_ms = int((time.perf_counter() - start) * 1000)

    text = response.text or ""
    return parse_json_response(text), text, latency_ms


def pct_error(predicted: float, truth: float) -> float | None:
    if truth is None or predicted is None:
        return None
    if truth == 0:
        return 0.0 if predicted == 0 else None
    return abs(predicted - truth) / truth * 100.0


def run() -> int:
    key, model = load_env()
    client = genai.Client(api_key=key)

    truth_df = load_ground_truth()
    photo_files = {p.name: p for p in MEALS_DIR.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"}}

    if not photo_files:
        sys.exit(f"No photos in {MEALS_DIR}. Drop meals in there first.")

    rows: list[Row] = []
    for _, gt in truth_df.iterrows():
        fn = gt["filename"]
        print(f"[{len(rows) + 1}/{len(truth_df)}] {fn} ... ", end="", flush=True)
        if fn not in photo_files:
            print("SKIP (file not found)")
            rows.append(Row(fn, gt["meal_name"], gt.to_dict(), None, "", "file_not_found", 0, None))
            continue

        try:
            parsed, raw, latency = analyze_photo(client, model, photo_files[fn])
            error = None if parsed else "json_parse_failed"
            pred = {
                "calories": parsed.get("total_calories") if parsed else None,
                "protein_g": parsed.get("total_protein_g") if parsed else None,
                "carbs_g": parsed.get("total_carbs_g") if parsed else None,
                "fat_g": parsed.get("total_fat_g") if parsed else None,
                "fiber_g": parsed.get("total_fiber_g") if parsed else None,
            } if parsed else None
            confidence = parsed.get("confidence") if parsed else None
            rows.append(Row(fn, gt["meal_name"], gt.to_dict(), pred, raw, error, latency, confidence))
            print(f"ok ({latency}ms, conf={confidence})")
        except Exception as exc:
            print(f"FAIL {type(exc).__name__}: {exc}")
            rows.append(Row(fn, gt["meal_name"], gt.to_dict(), None, "", f"{type(exc).__name__}: {exc}", 0, None))

    # Build per-row results
    results = []
    for r in rows:
        record = {
            "filename": r.filename,
            "meal_name": r.meal_name,
            "error": r.error or "",
            "latency_ms": r.latency_ms,
            "confidence": r.confidence,
        }
        for m in METRICS:
            truth_val = r.truth.get(m)
            pred_val = r.predicted.get(m) if r.predicted else None
            record[f"truth_{m}"] = truth_val
            record[f"pred_{m}"] = pred_val
            record[f"err_pct_{m}"] = pct_error(pred_val, truth_val) if pred_val is not None else None
        results.append(record)

    results_df = pd.DataFrame(results)
    RESULTS_DIR.mkdir(exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_csv = RESULTS_DIR / f"run_{stamp}.csv"
    results_df.to_csv(out_csv, index=False)

    # Summary
    print("\n" + "=" * 60)
    print("ACCURACY SUMMARY")
    print("=" * 60)
    for m in METRICS:
        col = f"err_pct_{m}"
        series = results_df[col].dropna()
        if series.empty:
            print(f"{m:12s}  no valid rows")
            continue
        median_err = series.median()
        mean_err = series.mean()
        within_20 = (series <= 20).mean() * 100
        print(f"{m:12s}  median={median_err:5.1f}%  mean={mean_err:5.1f}%  within±20%: {within_20:4.0f}%")

    fails = results_df[results_df["error"].astype(bool)]
    print(f"\nrows: {len(results_df)}  failures: {len(fails)}")
    print(f"median latency: {int(results_df['latency_ms'].replace(0, pd.NA).dropna().median() or 0)}ms")
    print(f"\nsaved: {out_csv}")

    # Kill-criteria check
    cal_series = results_df["err_pct_calories"].dropna()
    if len(cal_series) >= 20:
        median_cal = cal_series.median()
        verdict = "PASS" if median_cal <= 25 else "FAIL"
        print(f"\nKILL-CRITERIA (median calorie err ≤ 25%): {verdict} ({median_cal:.1f}%)")
    else:
        print(f"\nKILL-CRITERIA: need 20+ valid rows, got {len(cal_series)}. Add more meals.")

    return 0


if __name__ == "__main__":
    sys.exit(run())
