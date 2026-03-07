#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUZZ_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib.sh
source "$FUZZ_ROOT/scripts/lib.sh"

STATE_FILE="$FUZZ_ROOT/artifacts/.rotation-index"
SMOKE_MARKER="$FUZZ_ROOT/artifacts/.smoke-complete"
SEQUENCE=(
  psbt-transaction psbt-transaction psbt-transaction psbt-transaction psbt-transaction
  psbt-transaction psbt-transaction psbt-transaction psbt-transaction psbt-transaction
  descriptor-miniscript descriptor-miniscript descriptor-miniscript descriptor-miniscript descriptor-miniscript descriptor-miniscript descriptor-miniscript
  block-message block-message block-message
)

if [[ ! -f "$SMOKE_MARKER" ]]; then
  "$FUZZ_ROOT/scripts/smoke-all.sh"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$SMOKE_MARKER"
fi

idx=0
if [[ -f "$STATE_FILE" ]]; then
  idx="$(cat "$STATE_FILE")"
fi

slot=$((idx % ${#SEQUENCE[@]}))
target="${SEQUENCE[$slot]}"
next=$((idx + 1))
printf '%s' "$next" > "$STATE_FILE"

echo "[rotation] slot=$slot target=$target"
"$SCRIPT_DIR/run-campaign.sh" --target "$target" --mode long --hours 6
