# Payment Transaction Reconciliation

Implement a Python CLI program that processes payment transactions from a CSV file and produces a JSON summary.

## Input

The program accepts a CSV file containing payment transactions.

The CSV has the following columns:

- `tx_id`: Transaction identifier. Multiple rows may share the same ID.
- `timestamp`: Transaction timestamp in ISO-8601 format.
- `amount`: Transaction amount as an integer.
- `status`: Transaction status.

Timestamps include timezone information and may use different UTC offsets, including the `Z` suffix.

## Processing Rules

1. The program must accept a CSV file path as a command-line argument.
2. Running the program with `--help` must display usage information and exit successfully.
3. If multiple records have the same `tx_id`, retain only the record with the latest timestamp.
4. Timestamp comparisons must reflect the actual chronological order, regardless of timezone offsets.
5. If two records represent the same instant, retain the record appearing later in the CSV.
6. Deduplication must happen before calculating the summary.
7. Only transactions with status `VALID` contribute to the total valid amount and valid count.
8. Transactions with status `FAILED` contribute to the failed count.
9. Transactions with status `PENDING` must be excluded from all summary calculations.

## Output

The program must print a valid JSON object to standard output containing exactly these three fields:

- `total_valid_amount`: Sum of the amounts of retained VALID transactions.
- `valid_count`: Number of retained VALID transactions.
- `failed_count`: Number of retained FAILED transactions.

All three output values must be integers.

## Execution

The program should be executable using:

`python /app/reconcile.py <input.csv>`

Use Python's standard library. No external dependencies are required.

## Implementation Guidance

The provided `reconcile.py` is an existing implementation that must be corrected. Inspect the existing source code and make the smallest necessary changes to fix its behavior. Preserve the existing program structure and unrelated functionality. Do not replace the entire implementation with a newly written program.

Use non-interactive shell commands to inspect, modify, and test files. Avoid launching interactive text editors such as `nano` or `vim`.

For complex code modifications, prefer writing a temporary Python patch script or using a heredoc instead of performing many sequential line-number-based sed edits. After modifying the program, run `python3 -m py_compile reconcile.py` before testing its behavior.
