# Harbor RL Experiment Notes

## 1. Task Overview

Task: Payment Transaction Reconciliation

Three independent verifier checks:
1. CLI help handling.
2. Correct VALID / FAILED / PENDING status filtering.
3. Timezone-aware transaction deduplication.

### Reward Design

Original binary verifier:
- All three checks pass: 1.0
- Otherwise: 0.0

Dense verifier:
- CLI help: 1/3
- Status filtering: 1/3
- Timezone-aware deduplication: 1/3

Dense reward = sum of weights for passed checks.

## 2. Baseline Experiment

Model: terminus-2 with gemini-2.5-flash

Job: jobs/2026-11-15__19-39-55

| Trial | ID | Binary reward | Outcome |
|---|---|---:|---|
| 1 | wk9fXtv | 1.0 | Passed |
| 2 | 2USzY7c | 1.0 | Passed |
| 3 | QcxjtW9 | 0.0 | AgentTimeoutError |

Harbor-reported mean binary reward: 0.667.

Trajectory observations:
- Both successful agents rewrote reconcile.py instead of inspecting the starter implementation.
- Trial 1 created a replacement implementation using a heredoc and tested a CSV.
- Trial 2 created a replacement implementation and marked the task complete without running a functional test.
- Trial 3 became stuck in the interactive Nano editor and timed out.

The two successful binary trials passed all three verifier checks. Their dense reward is inferred to be 1.0, but their code was not independently replayed under the dense verifier. The timed-out trial has no independently verified dense score.

## 3. Ablation Design

The initial controlled instruction change asked agents to:
- Inspect the existing reconcile.py.
- Make minimal targeted corrections.
- Preserve unrelated code.
- Avoid interactive editors such as Nano and Vim.

A later refinement added:
- Prefer Python patch scripts or heredocs over repeated line-number-based sed edits.
- Run python3 -m py_compile reconcile.py before functional testing.

The model, starter code, verifier test cases, and timeout configuration were retained.

## 4. Refined Ablation Results

The three evaluated coding attempts were collected across two jobs. The cancelled Docker trial is excluded.

Jobs:
- jobs/2026-11-16__09-43-40
- jobs/2026-11-16__09-52-10

| Trial | ID | Checks passed | Binary | Dense |
|---|---|---:|---:|---:|
| 1 | KRq5Cm9 | 0/3 | 0.0 | 0.000000 |
| 2 | WXTACr4 | 0/3 | 0.0 | 0.000000 |
| 3 | YXbnyWW | 2/3 | 0.0 | 0.666667 |

Trajectory observations:

KRq5Cm9:
- Inspected the starter code.
- Failed CLI help, status filtering, and timezone-aware deduplication.

WXTACr4:
- Inspected the starter code.
- Attempted targeted sed modifications.
- Introduced an indentation error that caused all three checks to fail.

YXbnyWW:
- Inspected the starter code.
- Corrected timezone-aware deduplication.
- Correctly excluded PENDING transactions.
- Missed CLI help handling.
- Initially used datetime.fromisoformat incorrectly, diagnosed the AttributeError, and corrected the call.

Ablation group binary mean: 0.000000
Ablation group dense mean: 0.222222

## 5. Group Advantage Calculations

Formula:

Advantage = Trial Reward - Group Mean

### Baseline Binary

Rewards: [1.0, 1.0, 0.0]

Mean: 0.666667

Advantages:
[+0.333333, +0.333333, -0.666667]

The third trial timed out. Its zero is Harbor's recorded outcome, not a verifier-tested coding failure.

### Baseline Dense

The two successful binary trials imply three passed checks each, so their dense scores are inferred as 1.0 each.

The third trial has no independently verified dense score.

For the two successful trials:
Mean: 1.0
Advantages: [0.0, 0.0]

### Ablation Binary

Rewards: [0.0, 0.0, 0.0]

Mean: 0.0

Advantages:
[0.0, 0.0, 0.0]

### Ablation Dense

Rewards: [0.0, 0.0, 0.666667]

Mean: 0.222222

Advantages:
[-0.222222, -0.222222, +0.444445]

## 6. Main Findings

1. Baseline agents preferred rewriting the entire implementation instead of debugging the starter code.
2. The ablation instructions encouraged inspection and targeted edits.
3. Targeted edits introduced new risks, including indentation errors and incorrect datetime imports.
4. The final ablation attempt passed two of three checks.
5. Binary rewards hid partial progress: all ablation agents received zero despite different levels of correctness.
6. Dense rewards distinguished the partially correct solution and produced a non-zero relative advantage signal.

## 7. Important Experimental Limitations

- The baseline third trial timed out.
- Several intermediate ablation runs encountered API rate limits, service unavailability, Docker cancellation, or agent timeouts.
- The refined ablation's third evaluated attempt was run as a separate replacement job.
- Harbor artifact manifests did not contain the modified reconcile.py source snapshots.
- Dense rewards for ablation were reconstructed from the recorded independent verifier outputs, not obtained by replaying saved source snapshots.
- Baseline dense scores for the two successful trials are inferred from their full binary passes, not independently replayed.
- The results are a small qualitative experiment and should not be presented as statistically conclusive.

## 8. Remaining Work

- Implement solution/hack.sh.
- Harden the dense verifier against reward hacking.
- Verify solve.sh scores 1.0 and hack.sh scores 0.0.
- Demonstrate partial reward mutation.
- Record the five-minute Loom video.
- Complete README.md and submission packaging.

## 9. Red-Team Verifier and Anti-Cheat Results

### Naive verifier exploit

Created solution/hack.sh, which installs a fake reconcile.py.
It counts CSV data rows and returns hardcoded JSON for the
known three-row and two-row verifier cases.

Result against naive dense verifier:
- Harbor job: 2026-11-16__10-27-03
- Reward: 1.0
- Finding: The naive verifier was vulnerable to reward hacking.

### Hardened verifier

Added randomized transaction IDs, amounts, statuses, timestamps,
and duplicate IDs. Added an unweighted generalization gate that
compares the complete program output against an independently
calculated expected result.

The three primary checks retain equal weights of 1/3 each.
Failure of the generalization gate forces the total reward to 0.

### Anti-cheat validation

| Implementation | Verifier | Reward |
|---|---|---:|
| hack.sh | Naive dense verifier | 1.0 |
| solve.sh | Hardened verifier | 1.0 |
| hack.sh | Hardened verifier | 0.0 |
| Restored solve.sh | Hardened verifier | 1.0 |

Conclusion: The predictable verifier could be exploited by a
hardcoded implementation. Randomized inputs and the independent
generalization gate blocked this specific exploit while preserving
full reward for the genuine solution.
