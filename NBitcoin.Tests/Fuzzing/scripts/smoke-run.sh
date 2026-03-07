#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

TARGET=""
HARNESS=""
TIMEOUT_SEC=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --harness) HARNESS="$2"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 --target <target> [--harness <dll>] [--timeout-sec <n>]" >&2
  exit 2
fi
validate_target "$TARGET"
require_cmd dotnet

if [[ -z "$HARNESS" ]]; then
  OUT_DIR="$(create_run_dir "$TARGET" "smoke-build")/out"
  publish_target "$TARGET" "$OUT_DIR" "no"
  HARNESS="$OUT_DIR/$(assembly_for_target "$TARGET").dll"
fi

CORPUS_DIR="$(corpus_for_target "$TARGET")"
if [[ ! -d "$CORPUS_DIR" ]]; then
  echo "Corpus directory not found: $CORPUS_DIR" >&2
  exit 2
fi

TIMEOUT_CMD="$(timeout_bin || true)"
SEED_COUNT=0
while IFS= read -r seed; do
  SEED_COUNT=$((SEED_COUNT + 1))
  if [[ -n "$TIMEOUT_CMD" ]]; then
    "$TIMEOUT_CMD" "${TIMEOUT_SEC}s" dotnet "$HARNESS" "$seed" </dev/null >/dev/null
  else
    dotnet "$HARNESS" "$seed" </dev/null >/dev/null
  fi
done < <(find "$CORPUS_DIR" -maxdepth 1 -type f | sort)

echo "[smoke] target=$TARGET seeds=$SEED_COUNT status=ok"
