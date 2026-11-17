#!/usr/bin/env bash
set -euo pipefail

cat > /app/reconcile.py <<'PY'
import argparse
import csv
from datetime import datetime, timezone
import json


def parse_timestamp(value):
    normalized = value.strip()
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    parsed = datetime.fromisoformat(normalized)
    if parsed.utcoffset() is None:
        raise ValueError("timestamp must include a timezone")
    return parsed.astimezone(timezone.utc)


def main():
    parser = argparse.ArgumentParser(description="Summarize payment transactions.")
    parser.add_argument("csv_file", help="path to the transactions CSV file")
    args = parser.parse_args()

    latest = {}
    with open(args.csv_file, newline="", encoding="utf-8") as source:
        for row in csv.DictReader(source):
            tx_id = row["tx_id"]
            timestamp = parse_timestamp(row["timestamp"])
            previous = latest.get(tx_id)
            # >= makes the later CSV row win when timestamps represent one instant.
            if previous is None or timestamp >= previous[0]:
                latest[tx_id] = (timestamp, row)

    total_valid_amount = 0
    valid_count = 0
    failed_count = 0
    for _, row in latest.values():
        status = row["status"].strip().upper()
        if status == "VALID":
            total_valid_amount += int(row["amount"])
            valid_count += 1
        elif status == "FAILED":
            failed_count += 1

    print(json.dumps({
        "total_valid_amount": total_valid_amount,
        "valid_count": valid_count,
        "failed_count": failed_count,
    }))


if __name__ == "__main__":
    main()
PY
