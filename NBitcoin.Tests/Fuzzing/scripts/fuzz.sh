#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUZZ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

target_to_project() {
  case "$1" in
    psbt-transaction) echo "$FUZZ_ROOT/targets/NBitcoin.Fuzzing.PsbtTransaction/NBitcoin.Fuzzing.PsbtTransaction.csproj" ;;
    descriptor-miniscript) echo "$FUZZ_ROOT/targets/NBitcoin.Fuzzing.DescriptorMiniscript/NBitcoin.Fuzzing.DescriptorMiniscript.csproj" ;;
    block-message) echo "$FUZZ_ROOT/targets/NBitcoin.Fuzzing.BlockMessage/NBitcoin.Fuzzing.BlockMessage.csproj" ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
KISS wrapper for local fuzzing operations.

Usage:
  ./scripts/fuzz.sh smoke
  ./scripts/fuzz.sh run [target] [--ephemeral] [--rebuild] [--timeout-ms N]
  ./scripts/fuzz.sh triage [target] [--max-cases N] [--progress-every N] [--minimize]
  ./scripts/fuzz.sh replay
  ./scripts/fuzz.sh status

Targets:
  psbt-transaction (default)
  descriptor-miniscript
  block-message
EOF
}

run_smoke() {
  "$SCRIPT_DIR/smoke-all.sh"
}

run_campaign() {
  local target="psbt-transaction"
  local ephemeral=0
  local rebuild=0
  local timeout_ms=10000

  if [[ $# -gt 0 && "$1" != --* ]]; then
    target="$1"
    shift
  fi

  local project
  project="$(target_to_project "$target")" || {
    echo "Unknown target: $target" >&2
    exit 2
  }

  local args=(
    "$SCRIPT_DIR/fuzz-container.sh"
    --project "$project"
    --input "$FUZZ_ROOT/corpus/$target"
    --dictionary "$FUZZ_ROOT/Dictionary.txt"
    --timeout-ms "$timeout_ms"
  )

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ephemeral) ephemeral=1; shift ;;
      --rebuild) rebuild=1; shift ;;
      --timeout-ms) timeout_ms="$2"; shift 2 ;;
      *) echo "Unknown arg for run: $1" >&2; exit 2 ;;
    esac
  done

  args=(
    "$SCRIPT_DIR/fuzz-container.sh"
    --project "$project"
    --input "$FUZZ_ROOT/corpus/$target"
    --dictionary "$FUZZ_ROOT/Dictionary.txt"
    --timeout-ms "$timeout_ms"
  )
  [[ $ephemeral -eq 1 ]] && args+=(--ephemeral)
  [[ $rebuild -eq 1 ]] && args+=(--rebuild)

  "${args[@]}"
}

run_triage() {
  local target=""
  local max_cases=200
  local progress_every=25
  local minimize=0

  if [[ $# -gt 0 && "$1" != --* ]]; then
    target="$1"
    shift
  fi

  local args=("$SCRIPT_DIR/triage.sh" --max-cases "$max_cases" --progress-every "$progress_every")
  [[ -n "$target" ]] && args+=(--target "$target")

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-cases) max_cases="$2"; shift 2 ;;
      --progress-every) progress_every="$2"; shift 2 ;;
      --minimize) minimize=1; shift ;;
      *) echo "Unknown arg for triage: $1" >&2; exit 2 ;;
    esac
  done

  args=("$SCRIPT_DIR/triage.sh" --max-cases "$max_cases" --progress-every "$progress_every")
  [[ -n "$target" ]] && args+=(--target "$target")
  [[ $minimize -eq 1 ]] && args+=(--minimize)

  "${args[@]}"
}

run_status() {
  echo "[status] open findings by target"
  if [[ -f "$FUZZ_ROOT/regressions/manifest.json" ]]; then
    jq -r '.entries
      | group_by(.target)
      | .[]
      | "\(. [0].target): open=\(map(select(.status=="open"))|length) fixed=\(map(select(.status=="fixed"))|length) total=\(length)"' \
      "$FUZZ_ROOT/regressions/manifest.json"
  else
    echo "manifest not found"
  fi
  echo
  echo "[status] latest metrics"
  "$SCRIPT_DIR/collect-metrics.sh"
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 2; }
shift || true

case "$cmd" in
  smoke) run_smoke "$@" ;;
  run) run_campaign "$@" ;;
  triage) run_triage "$@" ;;
  replay) "$SCRIPT_DIR/replay-regressions.sh" "$@" ;;
  status) run_status "$@" ;;
  help|-h|--help) usage ;;
  *) echo "Unknown command: $cmd" >&2; usage; exit 2 ;;
esac
