#!/usr/bin/env bash
set -uo pipefail

mkdir -p /logs/verifier

python3 - <<'PY'
import csv
import json
import random
import secrets
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

APP = "/app/reconcile.py"
CHECKS = ("CLI help", "status filtering", "timezone-aware deduplication")
WEIGHTS = {name: 1 / 3 for name in CHECKS}
results = {}
generalization_passed = False


def report(name, passed, details=""):
    results[name] = bool(passed)
    print(f"{'PASS' if passed else 'FAIL'}: {name}" + (f" - {details}" if not passed else ""))


def random_tx_id():
    return "TX" + secrets.token_hex(10).upper()


def random_amount():
    return random.SystemRandom().randint(1, 1_000_000)


def random_status():
    return secrets.choice(("VALID", "FAILED", "PENDING"))


def write_csv(directory, name, rows):
    path = Path(directory) / f"{name}.csv"
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(("tx_id", "timestamp", "amount", "status"))
        writer.writerows(rows)
    return path


def run_app(path):
    return subprocess.run(
        [sys.executable, APP, str(path)], capture_output=True, text=True, timeout=10
    )


def parse_and_validate_output(stdout):
    try:
        actual = json.loads(stdout)
    except (json.JSONDecodeError, TypeError):
        return None
    expected_keys = {"total_valid_amount", "valid_count", "failed_count"}
    if type(actual) is not dict or set(actual) != expected_keys:
        return None
    if any(type(actual[key]) is not int for key in expected_keys):
        return None
    return actual


def reference_summary(rows):
    """Independent verifier model: retain the max UTC instant, breaking ties by row order."""
    retained = {}
    for index, row in enumerate(rows):
        tx_id, timestamp, amount, status = row
        instant = datetime.fromisoformat(timestamp.replace("Z", "+00:00")).astimezone(timezone.utc)
        previous = retained.get(tx_id)
        if previous is None or instant >= previous[0]:
            retained[tx_id] = (instant, index, int(amount), status)

    total = valid = failed = 0
    for _, _, amount, status in retained.values():
        if status == "VALID":
            total += amount
            valid += 1
        elif status == "FAILED":
            failed += 1
    return {"total_valid_amount": total, "valid_count": valid, "failed_count": failed}


def check_csv(name, directory, rows, expected):
    try:
        result = run_app(write_csv(directory, name.replace(" ", "_"), rows))
        if result.returncode != 0:
            report(name, False, f"exit {result.returncode}: {result.stderr.strip()}")
            return
        actual = parse_and_validate_output(result.stdout)
        report(name, actual is not None and actual == expected,
               f"expected {expected}, got {actual if actual is not None else 'malformed output'}")
    except (OSError, subprocess.SubprocessError, csv.Error, ValueError) as exc:
        report(name, False, str(exc))


try:
    help_result = subprocess.run(
        [sys.executable, APP, "--help"], capture_output=True, text=True, timeout=10
    )
    report("CLI help", help_result.returncode == 0 and "usage:" in help_result.stdout.lower(),
           f"exit {help_result.returncode}: {help_result.stderr.strip() or help_result.stdout.strip()}")
except (OSError, subprocess.SubprocessError) as exc:
    report("CLI help", False, str(exc))

with tempfile.TemporaryDirectory() as directory:
    # Random unique IDs and a random number of rows, with all three statuses represented.
    status_rows = []
    status_count = random.SystemRandom().randint(6, 18)
    for i in range(status_count):
        status = ("VALID", "FAILED", "PENDING")[i % 3]
        status_rows.append([
            random_tx_id(), f"2026-01-{1 + i % 28:02d}T{ i % 24:02d}:00:00Z",
            random_amount(), status,
        ])
    random.SystemRandom().shuffle(status_rows)
    check_csv("status filtering", directory, status_rows, reference_summary(status_rows))

    # Different offsets reverse the textual/local ordering; the tie proves later CSV row wins.
    tz_rows = [
        [random_tx_id(), "2026-02-01T10:30:00+03:00", random_amount(), random_status()],
        [None, "2026-02-01T08:00:00Z", random_amount(), random_status()],
        [None, "2026-02-01T05:00:00-04:00", random_amount(), random_status()],
        [random_tx_id(), "2026-02-02T12:00:00+05:00", random_amount(), random_status()],
        [None, "2026-02-02T07:00:00Z", random_amount(), random_status()],
    ]
    # Tie row 2 to row 1's ID: 08:00Z is later than 07:30Z; row 3 is 09:00Z.
    tz_rows[1][0] = tz_rows[0][0]
    tz_rows[2][0] = tz_rows[0][0]
    # Same instant for the second ID; retain its later CSV row.
    tz_rows[4][0] = tz_rows[3][0]
    check_csv("timezone-aware deduplication", directory, tz_rows, reference_summary(tz_rows))

    # Unweighted generalization gate: unique IDs, UTC timestamps, and all statuses.
    gate_rows = []
    gate_count = random.SystemRandom().randint(12, 30)
    gate_statuses = ["VALID", "FAILED", "PENDING"]
    gate_statuses.extend(random_status() for _ in range(gate_count - len(gate_statuses)))
    random.SystemRandom().shuffle(gate_statuses)
    base = datetime(2026, 3, 1, tzinfo=timezone.utc)
    for i in range(gate_count):
        instant = base.replace(day=1 + secrets.randbelow(27), hour=secrets.randbelow(24), minute=secrets.randbelow(60))
        gate_rows.append([
            random_tx_id(), instant.strftime("%Y-%m-%dT%H:%M:%SZ"),
            random_amount(), gate_statuses[i],
        ])
    random.SystemRandom().shuffle(gate_rows)
    gate_expected = reference_summary(gate_rows)
    try:
        gate_result = run_app(write_csv(directory, "generalization_gate", gate_rows))
        if gate_result.returncode != 0:
            report("anti-cheat generalization gate", False,
                   f"exit {gate_result.returncode}: {gate_result.stderr.strip()}")
        else:
            gate_actual = parse_and_validate_output(gate_result.stdout)
            generalization_passed = gate_actual is not None and gate_actual == gate_expected
            report("anti-cheat generalization gate", generalization_passed,
                   f"expected {gate_expected}, got {gate_actual if gate_actual is not None else 'malformed output'}")
    except (OSError, subprocess.SubprocessError, csv.Error, ValueError) as exc:
        report("anti-cheat generalization gate", False, str(exc))

reward = 0.0
if generalization_passed:
    reward = sum(WEIGHTS[name] for name in CHECKS if results.get(name, False))
reward = round(reward, 6)
Path("/logs/verifier/reward.txt").write_text(f"{reward:.6f}\n", encoding="utf-8")
print(f"\nPassed weighted checks: {sum(results.get(name, False) for name in CHECKS)}/{len(CHECKS)}")
print(f"Generalization gate: {'PASS' if generalization_passed else 'FAIL'}")
print(f"Dense reward: {reward:.6f}")
PY
