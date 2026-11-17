
#!/usr/bin/env bash
set -uo pipefail

mkdir -p /logs/verifier

if python3 - <<'PY'
import csv
import json
import subprocess
import sys
import tempfile
from pathlib import Path

APP = "/app/reconcile.py"
failures = 0


def report(name, passed, details=""):
    global failures
    if passed:
        print(f"PASS: {name}")
    else:
        failures += 1
        print(f"FAIL: {name} - {details}", file=sys.stderr)


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
            actual == expected
            and all(type(value) is int for value in actual.values())
        )
        report(name, passed, f"Expected {expected}, got {actual}")

    except Exception as exc:
        report(name, False, str(exc))


check_help()

with tempfile.TemporaryDirectory() as directory:
    # Check 2: Status filtering with unique transaction IDs.
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

    # Check 3: Latest duplicate transaction across timezones.
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

print(f"\nFailed checks: {failures}")
sys.exit(0 if failures == 0 else 1)
PY
then
    reward="1.0"
else
    reward="0.0"
fi

printf '%s\n' "$reward" > /logs/verifier/reward.txt
echo "Final reward: $reward"
