#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

stats_value_with_fallback() {
  local stats_file="$1"
  shift

  local key
  for key in "$@"; do
    local value
    value="$(stats_value "$stats_file" "$key")"
    if [[ "$value" != "0" && -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  done

  echo "0"
}

print_target_metrics() {
  local target="$1"
  local stats
  stats="$(find "$FUZZ_ROOT/artifacts/$target" -type f -path '*/findings/*/fuzzer_stats' 2>/dev/null | sort | tail -n1 || true)"
  if [[ -z "$stats" ]]; then
    echo "$target: no campaign runs yet"
    return
  fi

  local latest
  latest="$(dirname "$(dirname "$(dirname "$stats")")")"
  local run_name
  run_name="$(basename "$latest")"

  echo "$target"
  echo "  run: $run_name"
  echo "  execs_done: $(stats_value "$stats" "execs_done")"
  echo "  execs/sec: $(stats_value "$stats" "execs_per_sec")"
  echo "  paths_total: $(stats_value_with_fallback "$stats" "paths_total" "corpus_count")"
  echo "  unique_crashes: $(stats_value_with_fallback "$stats" "unique_crashes" "saved_crashes")"
  echo "  unique_hangs: $(stats_value_with_fallback "$stats" "unique_hangs" "saved_hangs")"
}

for target in "${TARGETS[@]}"; do
  print_target_metrics "$target"
done
