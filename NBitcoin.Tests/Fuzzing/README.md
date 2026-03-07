# NBitcoin Local-First Fuzzing

This directory contains the local fuzzing workflow for NBitcoin using AFL++ + SharpFuzz.
Current priority is a KISS, container-first workflow (no CI gate in this phase).

## Current Scope
- `psbt-transaction`
- `descriptor-miniscript`
- `block-message`

## Directory Layout
- `targets/`: one harness project per target.
- `common/`: shared helpers (input budget, runner, exception policy).
- `corpus/<target>/`: versioned seed corpus.
- `regressions/<target>/`: open/fixed regression inputs.
- `artifacts/<target>/`: campaign outputs (logs, metrics, crashes/hangs).
- `reports/`: triage reports.
- `scripts/`: operational scripts.

## KISS Daily Workflow
Use a single entrypoint: `scripts/fuzz.sh`.

```bash
# 1) Quick validation
./scripts/fuzz.sh smoke

# 2) Run a campaign (default target: psbt-transaction)
./scripts/fuzz.sh run

# Run a specific target
./scripts/fuzz.sh run descriptor-miniscript

# Ephemeral run (no persistent AFL queue)
./scripts/fuzz.sh run psbt-transaction --ephemeral

# 3) Triage findings
./scripts/fuzz.sh triage psbt-transaction

# 4) Replay regressions
./scripts/fuzz.sh replay

# 5) Current status
./scripts/fuzz.sh status
```

## Script Levels
Core (daily use):
- `scripts/fuzz.sh`
- `scripts/smoke-all.sh`
- `scripts/triage.sh`
- `scripts/replay-regressions.sh`
- `scripts/collect-metrics.sh`
- `scripts/fuzz-container.sh`

Internal (do not call directly):
- `scripts/fuzz-inner.sh`
- `scripts/smoke-run.sh`
- `scripts/lib.sh`

Advanced (optional):
- `scripts/advanced/run-campaign.sh` (native AFL host mode)
- `scripts/advanced/install-systemd-user.sh` (systemd timer setup)
- `scripts/advanced/fuzz.ps1` (PowerShell workflow)
- `scripts/advanced/rotation-once.sh` (single weighted rotation block)

## Optional Script
`scripts/advanced/rotation-once.sh` is kept as an optional manual rotation helper.
It runs one 6-hour native campaign block and rotates targets by predefined weights.

## Container Mode (Recommended)
Container mode reduces environment drift across macOS/Linux/CI.

First run (or after `Dockerfile.fuzz` changes):
```bash
./scripts/fuzz-container.sh \
  --project ./targets/NBitcoin.Fuzzing.PsbtTransaction/NBitcoin.Fuzzing.PsbtTransaction.csproj \
  --input ./corpus/psbt-transaction \
  --dictionary ./Dictionary.txt \
  --timeout-ms 10000 \
  --rebuild
```

Default behavior is hybrid mode:
- persistent AFL state in a Docker volume (resume between runs),
- selective export to host (`crashes`, `hangs`, `fuzzer_stats`, `plot_data`, `cmdline`):
  `artifacts/<target>/<YYYYmmddTHHMMSSZ>-container/findings`.

Useful options:
- `--rebuild`: rebuild image (`AFL++ 4.35c` + `SharpFuzz 2.2.0`).
- `--state-volume <name>`: explicit AFL state volume.
- `--no-state-volume`: disable persistence.
- `--ephemeral`: alias of `--no-state-volume`.
- `--instrument-pattern <regex>`: DLL instrumentation filter (default: `^NBitcoin\.dll$`).
- `--findings-dir <path>`: custom export destination.
- `--image <tag>`: custom image tag.

## macOS Architecture Note
For native AFL runs on macOS, `afl-fuzz` and `dotnet` must use the same architecture (`arm64`/`x86_64`):

```bash
file "$(command -v afl-fuzz)"
file "$(command -v dotnet)"
```
