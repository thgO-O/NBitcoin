#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUZZ_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib.sh
source "$FUZZ_ROOT/scripts/lib.sh"

TARGET=""
MODE="long"
HOURS="6"
TIMEOUT_MS="2000"
MEMORY="none"
SEED_TIMEOUT_SEC="8"
NO_INSTRUMENT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --hours) HOURS="$2"; shift 2 ;;
    --timeout-ms) TIMEOUT_MS="$2"; shift 2 ;;
    --memory) MEMORY="$2"; shift 2 ;;
    --seed-timeout-sec) SEED_TIMEOUT_SEC="$2"; shift 2 ;;
    --no-instrument) NO_INSTRUMENT=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 --target <target> [--mode smoke|long] [--hours n]" >&2
  exit 2
fi
validate_target "$TARGET"
require_cmd dotnet
require_cmd afl-fuzz

if [[ "$(uname -s)" == "Darwin" ]]; then
  afl_arch="$(file "$(command -v afl-fuzz)" | sed -nE 's/.*(x86_64|arm64).*/\1/p' | head -n1)"
  dotnet_arch="$(file "$(command -v dotnet)" | sed -nE 's/.*(x86_64|arm64).*/\1/p' | head -n1)"
  if [[ -n "$afl_arch" && -n "$dotnet_arch" && "$afl_arch" != "$dotnet_arch" && "${FUZZ_ALLOW_ARCH_MISMATCH:-0}" != "1" ]]; then
    echo "[campaign] error=arch-mismatch afl_arch=$afl_arch dotnet_arch=$dotnet_arch" >&2
    echo "[campaign] hint=install afl-fuzz for $dotnet_arch or run matching dotnet architecture" >&2
    echo "[campaign] hint=set FUZZ_ALLOW_ARCH_MISMATCH=1 to bypass this guard" >&2
    exit 2
  fi
fi

if [[ "$MODE" != "smoke" && "$MODE" != "long" ]]; then
  echo "mode must be smoke or long" >&2
  exit 2
fi

DURATION_SEC=$((HOURS * 3600))
if [[ "$MODE" == "smoke" ]]; then
  DURATION_SEC=300
fi

RUN_DIR="$(create_run_dir "$TARGET" "$MODE")"
OUT_RAW_DIR="$RUN_DIR/out-raw"
OUT_DIR="$RUN_DIR/out"
LOG_FILE="$RUN_DIR/afl.log"
AFL_OUT="$RUN_DIR/findings"
SUMMARY_FILE="$RUN_DIR/summary.json"
HARNESS_NAME="$(assembly_for_target "$TARGET")"
HARNESS_DLL="$OUT_DIR/$HARNESS_NAME.dll"
CORPUS_DIR="$(corpus_for_target "$TARGET")"
DICT_PATH="$FUZZ_ROOT/Dictionary.txt"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
AFL_DUMB_MODE=0

publish_target "$TARGET" "$OUT_RAW_DIR" "no"
"$FUZZ_ROOT/scripts/smoke-run.sh" --target "$TARGET" --harness "$OUT_RAW_DIR/$HARNESS_NAME.dll" --timeout-sec "$SEED_TIMEOUT_SEC"

rm -rf "$OUT_DIR"
cp -R "$OUT_RAW_DIR" "$OUT_DIR"

if [[ $NO_INSTRUMENT -eq 0 ]]; then
  set +e
  instrument_output_dir "$TARGET" "$OUT_DIR"
  instrument_ec=$?
  set -e
  if [[ $instrument_ec -ne 0 ]]; then
    echo "[campaign] warning=instrumentation_failed fallback=dumb-mode"
    rm -rf "$OUT_DIR"
    cp -R "$OUT_RAW_DIR" "$OUT_DIR"
    AFL_DUMB_MODE=1
  fi

  if [[ $AFL_DUMB_MODE -eq 0 && "$(uname -s)" != "Darwin" ]]; then
    first_seed="$(find "$CORPUS_DIR" -maxdepth 1 -type f | sort | head -n1 || true)"
    if [[ -n "$first_seed" ]]; then
      if dotnet "$HARNESS_DLL" "$first_seed" >/dev/null 2>&1; then
        replay_ec=0
      else
        replay_ec=$?
      fi
      if [[ $replay_ec -ne 0 ]]; then
        echo "[campaign] warning=instrumented_seed_replay_failed exit=$replay_ec fallback=dumb-mode"
        rm -rf "$OUT_DIR"
        cp -R "$OUT_RAW_DIR" "$OUT_DIR"
        AFL_DUMB_MODE=1
      fi
    fi
  fi
else
  AFL_DUMB_MODE=1
fi

if [[ "$(uname -s)" == "Darwin" && -z "${AFL_NO_FORKSRV:-}" ]]; then
  export AFL_NO_FORKSRV=1
fi

mkdir -p "$AFL_OUT"
export AFL_SKIP_BIN_CHECK=1

set +e
TIMEOUT_CMD="$(timeout_bin || true)"
AFL_DUMB_FLAG=""
if [[ $AFL_DUMB_MODE -eq 1 ]]; then
  AFL_DUMB_FLAG="-n"
fi
if [[ -n "$TIMEOUT_CMD" ]]; then
  "$TIMEOUT_CMD" -k 5 "${DURATION_SEC}s" \
    afl-fuzz \
      ${AFL_DUMB_FLAG:+$AFL_DUMB_FLAG} \
      -i "$CORPUS_DIR" \
      -o "$AFL_OUT" \
      -x "$DICT_PATH" \
      -m "$MEMORY" \
      -t "${TIMEOUT_MS}+" \
      -- dotnet "$HARNESS_DLL" 2>&1 | tee "$LOG_FILE"
  AFL_EXIT=${PIPESTATUS[0]}
else
  afl-fuzz \
    ${AFL_DUMB_FLAG:+$AFL_DUMB_FLAG} \
    -i "$CORPUS_DIR" \
    -o "$AFL_OUT" \
    -x "$DICT_PATH" \
    -m "$MEMORY" \
    -t "${TIMEOUT_MS}+" \
    -- dotnet "$HARNESS_DLL" 2>&1 | tee "$LOG_FILE"
  AFL_EXIT=${PIPESTATUS[0]}
fi
set -e

ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STATS_FILE="$AFL_OUT/default/fuzzer_stats"
execs_done="$(stats_value "$STATS_FILE" "execs_done")"
execs_per_sec="$(stats_value "$STATS_FILE" "execs_per_sec")"
paths_total="$(stats_value "$STATS_FILE" "paths_total")"
unique_crashes="$(stats_value "$STATS_FILE" "unique_crashes")"
unique_hangs="$(stats_value "$STATS_FILE" "unique_hangs")"

cat > "$SUMMARY_FILE" <<JSON
{
  "target": "$TARGET",
  "mode": "$MODE",
  "started_at_utc": "$STARTED_AT",
  "ended_at_utc": "$ENDED_AT",
  "duration_seconds": $DURATION_SEC,
  "dumb_mode": $AFL_DUMB_MODE,
  "afl_exit_code": $AFL_EXIT,
  "metrics": {
    "execs_done": "$execs_done",
    "execs_per_sec": "$execs_per_sec",
    "paths_total": "$paths_total",
    "unique_crashes": "$unique_crashes",
    "unique_hangs": "$unique_hangs"
  }
}
JSON

if [[ -f "$STATS_FILE" ]]; then
  cp "$STATS_FILE" "$RUN_DIR/fuzzer_stats.final"
fi

echo "[campaign] target=$TARGET mode=$MODE exit=$AFL_EXIT summary=$(relative_path "$SUMMARY_FILE")"
