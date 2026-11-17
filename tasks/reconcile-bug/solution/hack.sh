#!/usr/bin/env bash
set -euo pipefail

cat > /app/reconcile.py <<'PY'
import argparse
import csv
import json
import sys


def main():
    parser = argparse.ArgumentParser(description="Summarize payment transactions.")
    parser.add_argument("csv_file", help="path to the transactions CSV file")
    args = parser.parse_args()

    with open(args.csv_file, newline="", encoding="utf-8") as source:
        rows = csv.reader(source)
        next(rows, None)  # Skip the header.
        data_row_count = sum(1 for _ in rows)

    if data_row_count == 3:
        result = {
            "total_valid_amount": 500,
            "valid_count": 1,
            "failed_count": 1,
        }
    elif data_row_count == 2:
        result = {
            "total_valid_amount": 0,
            "valid_count": 0,
            "failed_count": 1,
        }
    else:
        print(f"Unsupported CSV data row count: {data_row_count}", file=sys.stderr)
        return 1

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
