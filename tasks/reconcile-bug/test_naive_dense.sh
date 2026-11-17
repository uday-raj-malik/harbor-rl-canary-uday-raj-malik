#!/usr/bin/env bash
set -uo pipefail

mkdir -p /logs/verifier

python3 - <<'PY'
import csv
import json
import subprocess
import sys
import tempfile
from pathlib import Path

APP = "/app/reconcile.py"

WEIGHTS = {
    "CLI help": 1 / 3,
    "status filtering": 1 / 3,
    "timezone-aware deduplication": 1 / 3,
}

results = {}


def report(name, passed, details=""):
    results[name] = passed

    if passed:
        print(f"PASS: {name}")
    else:
        print(f"FAIL: {name} - {details}", file=sys.stderr)

    return passed


def check_help():
    try:
        result = subprocess.run(
            [sys.executable, APP, "--help"],
            capture_output=True,
            text=True,
            timeout=10,
        )

        passed = (
            result.returncode == 0
            and "usage:" in result.stdout.lower()
        )

        report("CLI help", passed, result.stderr or result.stdout)

    except Exception as exc:
        report("CLI help", False, str(exc))


def check_csv(name, directory, rows, expected):
    path = Path(directory) / f"{name}.csv"

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["tx_id", "timestamp", "amount", "status"])
        writer.writerows(rows)

    try:
        result = subprocess.run(
            [sys.executable, APP, str(path)],
            capture_output=True,
            text=True,
            timeout=10,
        )

        if result.returncode != 0:
            report(name, False, result.stderr)
            return

        actual = json.loads(result.stdout)

        passed = (
            type(actual) is dict
            and actual == expected
            and all(type(value) is int for value in actual.values())
        )

        report(name, passed, f"Expected {expected}, got {actual}")

    except Exception as exc:
        report(name, False, str(exc))


check_help()

with tempfile.TemporaryDirectory() as directory:

    # Check 2: Status filtering.
    check_csv(
        "status filtering",
        directory,
        [
            ["TX001", "2026-01-01T10:00:00Z", 500, "VALID"],
            ["TX002", "2026-01-01T11:00:00Z", 200, "FAILED"],
            ["TX003", "2026-01-01T12:00:00Z", 300, "PENDING"],
        ],
        {
            "total_valid_amount": 500,
            "valid_count": 1,
            "failed_count": 1,
        },
    )

    # Check 3: Timezone-aware deduplication.
    check_csv(
        "timezone-aware deduplication",
        directory,
        [
            ["TX001", "2026-01-01T10:00:00+02:00", 500, "VALID"],
            ["TX001", "2026-01-01T09:30:00Z", 700, "FAILED"],
        ],
        {
            "total_valid_amount": 0,
            "valid_count": 0,
            "failed_count": 1,
        },
    )


# Calculate weighted dense reward.
reward = sum(
    WEIGHTS[name]
    for name, passed in results.items()
    if passed
)

reward = round(reward, 6)

Path("/logs/verifier/reward.txt").write_text(
    f"{reward:.6f}\n",
    encoding="utf-8",
)

print(f"\nPassed checks: {sum(results.values())}/{len(WEIGHTS)}")
print(f"Dense reward: {reward:.6f}")

PY
