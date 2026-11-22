#!/bin/bash
# Runs the unit tests with coverage and fails if logic-code line coverage is below MIN_COVERAGE (default 95).
# SwiftUI views and OS glue can't be unit-tested in a Swift package, so those files are excluded explicitly.
# Usage: scripts/coverage.sh [extra swift test arguments]
set -euo pipefail
cd "$(dirname "$0")/.."

MIN_COVERAGE="${MIN_COVERAGE:-95}"
EXCLUDED='/UI/Views\.swift$|/UI/QuickPanel\.swift$|/UI/SettingsView\.swift$|/UI/Theme\.swift$|/PromptForgeApp\.swift$|/System/SystemIntegration\.swift$|/Providers/Keychain\.swift$|/AppState\+System\.swift$'

swift test --enable-code-coverage "$@"
JSON="$(swift test --show-codecov-path)"

python3 -I - "$JSON" "$MIN_COVERAGE" "$EXCLUDED" <<'PY'
import json, re, sys

path, minimum, excluded = sys.argv[1], float(sys.argv[2]), re.compile(sys.argv[3])
files = json.load(open(path))["data"][0]["files"]
rows, covered, total = [], 0, 0
for f in files:
    name = f["filename"]
    if "/Sources/" not in name or excluded.search(name):
        continue
    lines = f["summary"]["lines"]
    covered += lines["covered"]
    total += lines["count"]
    rows.append((lines["percent"], lines["covered"], lines["count"], name.split("/Sources/", 1)[1]))

print(f"\n{'Lines':>11}  {'Cover':>7}  File")
for pct, c, n, name in sorted(rows):
    print(f"{c:>5}/{n:<5}  {pct:6.1f}%  {name}")
pct = 100.0 * covered / total if total else 100.0
print(f"{covered:>5}/{total:<5}  {pct:6.1f}%  TOTAL (logic code; views and OS glue excluded)")
if pct < minimum:
    sys.exit(f"\nCoverage {pct:.1f}% is below the {minimum:g}% minimum. Add tests for the uncovered lines.")
print(f"\nCoverage {pct:.1f}% meets the {minimum:g}% minimum.")
PY
