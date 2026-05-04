#!/usr/bin/env python3
"""Summarize the v11 regression 3-run results into a compact table."""
import json, glob, os, statistics
LOG_DIR = os.path.join(os.path.dirname(__file__), "..", "experiment_log")
runs = sorted(glob.glob(os.path.join(LOG_DIR, "regression_v11_run*_2026*.json")))
print(f"Found {len(runs)} run JSON files")
runs = runs[-3:]
totals = []
per_stage = {f"stage_{i}": [] for i in range(7)}
flags = []
for path in runs:
    print("\n--- " + os.path.basename(path))
    d = json.load(open(path))
    total = d.get("_total_duration", -1)
    totals.append(total)
    print(f"  total: {total:.1f}s")
    print(f"  stages:")
    for k in sorted(per_stage.keys()):
        st = d.get(k, {})
        s = st.get("status")
        dur = st.get("duration")
        print(f"    {k}: {s} {dur:.1f}s" if dur else f"    {k}: {s}")
        if dur:
            per_stage[k].append(dur)
    f = d.get("stage_6", {}).get("found")
    flags.append(f)
print("\n=== AVERAGES ===")
print(f"  total: avg {statistics.mean(totals):.1f}s  min {min(totals):.1f}s  max {max(totals):.1f}s")
for k in sorted(per_stage.keys()):
    if per_stage[k]:
        print(f"  {k}: avg {statistics.mean(per_stage[k]):.1f}s  min {min(per_stage[k]):.1f}s  max {max(per_stage[k]):.1f}s")
print(f"\nflags: {flags}")
