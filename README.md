# Harbor RL Submission — Uday Raj Malik (@uday-raj-malik)

## 1. Walkthrough Video

[Watch the 5-Minute Walkthrough](https://youtu.be/ooOplNSqmS4)

## 2. Task & Calibration Summary

**Task:** Payment Transaction Reconciliation

### Bugs

- **Bug 1 (Easy):** CLI argument handling did not correctly support `--help`.
- **Bug 2 (Medium):** PENDING transactions were incorrectly included in valid transaction totals and counts.
- **Bug 3 (Hard):** Duplicate transactions were compared using timestamp strings instead of actual chronological instants across timezone offsets.

### Calibration Scores

| Evaluation | Reward |
|---|---:|
| `nop` | 0.000 |
| `oracle` (`solve.sh`) | 1.000 |
| Partial Oracle (Bug 3 deliberately broken) | 0.667 |
| `hack.sh` against naive verifier | 1.000 |
| `hack.sh` against hardened verifier | 0.000 |
| Restored `solve.sh` against hardened verifier | 1.000 |

The partial-Oracle result demonstrates that the hardened verifier awards credit for the two correctly implemented checks while withholding credit for the deliberately broken timezone-aware deduplication check.

## 3. Ablation & RL Advantage Analysis

**Agent:** `terminus-2`
**Model:** Gemini 2.5 Flash
**Trials:** k=3, n=1 per evaluation trial

| Run | Trial 1 | Trial 2 | Trial 3 | Mean Binary | Mean Dense | Binary Advantages | Dense Advantages |
|---|---|---|---|---:|---:|---|---|
| **Baseline** — original task instructions | `wk9fXtv`: 1.000 / 1.000* | `2USzY7c`: 1.000 / 1.000* | `QcxjtW9`: 0.000 / N/A | 0.667 | N/A | +0.333, +0.333, -0.667 | N/A |
| **Ablation** — implementation guidance added and progressively refined | `KRq5Cm9`: 0.000 / 0.000 | `WXTACr4`: 0.000 / 0.000 | `YXbnyWW`: 0.000 / 0.667 | 0.000 | 0.222 | 0.000, 0.000, 0.000 | -0.222, -0.222, +0.444 |

*The two successful baseline trials passed all three functional checks, so their dense values are inferred as 1.000. They were not independently replayed under the dense verifier. The third baseline trial timed out, so its dense score and the complete baseline dense group advantage are unavailable.*

### Advantage Calculation

I use the group-mean difference:

\[
A_i = R_i - \bar R
\]

**Baseline binary rewards**

\[
[1,1,0], \qquad \bar R = 0.667
\]

\[
A = [+0.333,+0.333,-0.667]
\]

The third zero is Harbor's recorded timeout reward, not a verifier-confirmed coding failure.

**Ablation binary rewards**

\[
[0,0,0], \qquad \bar R = 0
\]

\[
A = [0,0,0]
\]

**Ablation dense rewards**

\[
[0,0,\frac{2}{3}], \qquad \bar R = \frac{2}{9} \approx 0.222
\]

\[
A \approx [-0.222,-0.222,+0.444]
\]

The dense verifier distinguishes the partially successful third ablation trial, whereas binary grading assigns zero to all three attempts.

## 4. Trajectory Forensics (`trajectory.json`)

### Baseline failure: `QcxjtW9`

The agent attempted to open `vi reconcile.py`, but `vi` was unavailable. It subsequently entered Python code directly into Bash, causing command-not-found and syntax errors.

The agent then installed Nano, opened the file and incorrectly pasted the code, corrupting the editor buffer. It repeatedly tried to recover and eventually timed out.

The two successful baseline agents took a different approach: they wrote complete replacement implementations rather than debugging the original starter code.

### Ablation hypothesis and results

I introduced implementation guidance asking the agent to inspect the existing source, make minimal corrections and avoid interactive editors. The guidance was progressively refined to encourage safer non-interactive patching methods and syntax checks.

The three ablation attempts exposed different failure modes:

- **`KRq5Cm9`:** The agent inspected the source and attempted targeted edits, but introduced indentation and logic problems. It eventually timed out and failed all three checks.
- **`WXTACr4`:** The agent made multiple sequential `sed` modifications. The resulting implementation had an indentation error, causing all three checks to fail.
- **`YXbnyWW`:** The agent inspected `reconcile.py`, attempted targeted modifications using `sed`, ran `python3 -m py_compile` and tested its implementation with a CSV file. It corrected timezone-aware deduplication and PENDING status filtering but missed CLI help handling. It passed two of the three checks and received a reconstructed dense reward of 0.667.

This provides qualitative evidence that implementation guidance changed the agent's debugging behaviour. However, the guidance was refined between attempts, and the small sample size and execution failures mean this is not a perfectly controlled comparison. The results should therefore be interpreted as exploratory rather than conclusive evidence of a causal improvement.

## 5. Dense Reward & Anti-Cheat Design

### Dense reward weights

The three independent primary checks receive equal weights:

| Check | Weight |
|---|---:|
| CLI help | 0.333333 |
| Status filtering | 0.333333 |
| Timezone-aware deduplication | 0.333333 |

The verifier also has an unweighted generalization gate. It generates 12–30 randomized rows with unique transaction IDs, randomized integer amounts and statuses, and UTC timestamps. All three statuses are represented. The expected summary is calculated independently.

The gate must pass before any weighted reward is awarded. It is designed to catch hardcoded or narrowly specialized implementations without interfering with partial credit for the timezone-specific Bug 3 check.

### How `solution/hack.sh` cheated — and how I blocked it

The cheat script installs a fake `reconcile.py` that counts CSV data rows and returns hardcoded JSON for the predictable two-row and three-row verifier cases.

It received a reward of 1.000 against the naive verifier because the original tests used fixed inputs.

I hardened the verifier with randomized data and an independent generalization gate. The fake implementation could no longer predict the expected output and received 0.000, while the genuine solution continued to receive 1.000.

### Remaining reward-hacking risk

A more sophisticated agent could recognize input distributions or fixed structural patterns used by particular tests and special-case them. Further protection could include more varied randomized duplicate groups, broader timezone offsets, property-based testing and hidden test distributions.

No finite verifier eliminates all reward-hacking possibilities. The objective is to make genuine task completion more reliable than exploiting the tests.

## 6. AI Tool Workflow

- **AI coding tool:** OpenAI Codex CLI
- **Harbor evaluation agent:** `terminus-2`
- **Evaluation model:** Gemini 2.5 Flash

Codex CLI assisted with verifier development, the reward-hacking demonstration and verifier hardening.

The task instructions focused on the input format, expected output and business rules without identifying the exact buggy lines or revealing implementation fixes.

Trajectory inspection, verifier design, experiment comparison and RL advantage calculations were treated as separate evaluation activities.

## 7. Submission Contents

- `tasks/reconcile-bug/` — Harbor task definition, broken starter implementation, genuine solution, cheat script and verifiers.
- `jobs_summary/` — Baseline and ablation result and trajectory files for all six evaluated trials.
- `ai_transcripts/` — Exported Codex CLI sessions.
- `EXPERIMENT_NOTES.md` — Detailed experiment log and limitations.
- `README.md` — Task description, calibration results, reward design, trajectory analysis and video link.

The supplementary naive verifier is retained to document the reward-hacking demonstration.