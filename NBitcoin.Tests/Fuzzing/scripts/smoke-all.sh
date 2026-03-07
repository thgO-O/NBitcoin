#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

for target in "${TARGETS[@]}"; do
  "$SCRIPT_DIR/smoke-run.sh" --target "$target"
done
