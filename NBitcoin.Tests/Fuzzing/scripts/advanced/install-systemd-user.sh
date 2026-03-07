#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUZZ_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"

mkdir -p "$UNIT_DIR"

for unit in nbitcoin-fuzzing-rotation.service nbitcoin-fuzzing-rotation.timer; do
  sed "s#__FUZZ_ROOT__#$FUZZ_ROOT#g" "$FUZZ_ROOT/systemd/$unit" > "$UNIT_DIR/$unit"
done

systemctl --user daemon-reload
systemctl --user enable --now nbitcoin-fuzzing-rotation.timer
systemctl --user status nbitcoin-fuzzing-rotation.timer --no-pager
