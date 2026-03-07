#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_cmd jq
require_cmd dotnet

MANIFEST="$FUZZ_ROOT/regressions/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 2
fi

TIMEOUT_CMD="$(timeout_bin || true)"
TIMEOUT_SEC=5

harness_for_target() {
  local target="$1"
  local out_dir="$FUZZ_ROOT/artifacts/$target/replay-cache/out"
  local dll="$out_dir/$(assembly_for_target "$target").dll"

  if [[ ! -f "$dll" ]]; then
    publish_target "$target" "$out_dir" "no"
  fi

  echo "$dll"
}

run_dotnet_quiet() {
  local harness="$1"
  local input="$2"
  local timeout_sec="$3"
  local runner='
"$@"
rc=$?
exit "$rc"
'

  if [[ -n "$timeout_sec" ]]; then
    /bin/sh -c "$runner" sh "$TIMEOUT_CMD" "${timeout_sec}s" dotnet "$harness" "$input" </dev/null >/dev/null 2>&1
    return $?
  fi

  /bin/sh -c "$runner" sh dotnet "$harness" "$input" </dev/null >/dev/null 2>&1
  return $?
}

run_case() {
  local harness="$1"
  local input="$2"
  local expected="$3"

  for _ in 1 2 3; do
    if [[ "$expected" == "hang" && -n "$TIMEOUT_CMD" ]]; then
      if run_dotnet_quiet "$harness" "$input" "$TIMEOUT_SEC"; then
        ec=0
      else
        ec=$?
      fi
    else
      if run_dotnet_quiet "$harness" "$input" ""; then
        ec=0
      else
        ec=$?
      fi
    fi

    case "$expected" in
      clean)
        [[ $ec -eq 0 ]] || return 1
        ;;
      crash)
        [[ $ec -ne 0 && $ec -ne 124 ]] || return 1
        ;;
      hang)
        [[ $ec -eq 124 ]] || return 1
        ;;
      *)
        return 1
        ;;
    esac
  done

  return 0
}

TOTAL=0
PASSED=0
FAILED=0

while IFS= read -r entry; do
  TOTAL=$((TOTAL + 1))
  target="$(jq -r '.target' <<<"$entry")"
  status="$(jq -r '.status' <<<"$entry")"
  kind="$(jq -r '.kind' <<<"$entry")"
  id="$(jq -r '.id' <<<"$entry")"
  input_rel="$(jq -r '.input_path' <<<"$entry")"
  input="$FUZZ_ROOT/$input_rel"

  if [[ ! -f "$input" ]]; then
    echo "[replay] id=$id target=$target status=fail reason=missing-input"
    FAILED=$((FAILED + 1))
    continue
  fi

  expected="crash"
  if [[ "$status" == "fixed" ]]; then
    expected="clean"
  elif [[ "$kind" == "hang" ]]; then
    expected="hang"
  fi

  harness="$(harness_for_target "$target")"
  if run_case "$harness" "$input" "$expected"; then
    echo "[replay] id=$id target=$target status=pass expected=$expected"
    PASSED=$((PASSED + 1))
  else
    echo "[replay] id=$id target=$target status=fail expected=$expected"
    FAILED=$((FAILED + 1))
  fi
done < <(jq -c '.entries[] | select(.status == "open" or .status == "fixed")' "$MANIFEST")

echo "[replay-summary] total=$TOTAL passed=$PASSED failed=$FAILED"
[[ $FAILED -eq 0 ]]
