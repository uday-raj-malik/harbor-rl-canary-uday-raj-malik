import csv
import json
import sys


def main():
    if len(sys.argv) != 2:
        print("Usage: reconcile.py <transactions.csv>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    try:
        with open(path, newline="", encoding="utf-8") as source:
            transactions = {}
            for row in csv.DictReader(source):
                tx_id = row["tx_id"]
                timestamp = row["timestamp"]
                if tx_id not in transactions or timestamp >= transactions[tx_id]["timestamp"]:
                    transactions[tx_id] = row
    except (OSError, KeyError, csv.Error) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    total_valid_amount = 0
    valid_count = 0
    failed_count = 0
    for row in transactions.values():
        status = row["status"].strip().upper()
        amount = int(row["amount"])
        if status in ("VALID", "PENDING"):
            total_valid_amount += amount
            valid_count += 1
        elif status == "FAILED":
            failed_count += 1

    print(json.dumps({
        "total_valid_amount": total_valid_amount,
        "valid_count": valid_count,
        "failed_count": failed_count,
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
