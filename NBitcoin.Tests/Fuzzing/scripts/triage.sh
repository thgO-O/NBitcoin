#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_cmd jq
require_cmd dotnet
require_cmd sha256sum

MANIFEST="$FUZZ_ROOT/regressions/manifest.json"
TIMEOUT_CMD="$(timeout_bin || true)"
TARGET_FILTER="all"
TIMEOUT_SEC=5
SKIP_MINIMIZE=1
MAX_CASES=0
PROGRESS_EVERY=25

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_FILTER="$2"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="$2"; shift 2 ;;
    --minimize) SKIP_MINIMIZE=0; shift ;;
    --skip-minimize) SKIP_MINIMIZE=1; shift ;;
    --max-cases) MAX_CASES="$2"; shift 2 ;;
    --progress-every) PROGRESS_EVERY="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  cat > "$MANIFEST" <<JSON
{"version":1,"updated_at_utc":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","entries":[]}
JSON
fi

TARGET_LIST=()
if [[ "$TARGET_FILTER" == "all" ]]; then
  TARGET_LIST=("${TARGETS[@]}")
else
  validate_target "$TARGET_FILTER"
  TARGET_LIST=("$TARGET_FILTER")
fi

KNOWN_HASHES_FILE="$(mktemp)"
NEW_HASHES_FILE="$(mktemp)"
NEW_ROWS_FILE="$(mktemp)"
trap 'rm -f "$KNOWN_HASHES_FILE" "$NEW_HASHES_FILE" "$NEW_ROWS_FILE"' EXIT
jq -r '.entries[]?.signature_hash // empty' "$MANIFEST" | sort -u > "$KNOWN_HASHES_FILE"

hash_seen() {
  local hash="$1"
  grep -Fxq "$hash" "$KNOWN_HASHES_FILE" && return 0
  grep -Fxq "$hash" "$NEW_HASHES_FILE" && return 0
  return 1
}

mark_hash_seen() {
  local hash="$1"
  echo "$hash" >> "$NEW_HASHES_FILE"
}

signature_from_log() {
  local log_file="$1"
  local exline
  exline="$(grep -m1 -E 'Unhandled exception\.|Exception:' "$log_file" | sed -E 's/[[:space:]]+$//' || true)"
  [[ -n "$exline" ]] || exline="unknown-exception"
  local frames
  frames="$(grep -m3 -E '^[[:space:]]+at ' "$log_file" | sed -E 's/^[[:space:]]+at //' | sed -E 's/ in .*:line [0-9]+$//' | paste -sd'|' - || true)"
  printf '%s|%s' "$exline" "$frames"
}

LAST_SIGNATURE=""

run_dotnet_quiet() {
  local harness="$1"
  local input="$2"
  local output_file="$3"
  local runner='
"$@"
rc=$?
exit "$rc"
'

  set +e
  if [[ -n "$TIMEOUT_CMD" ]]; then
    /bin/sh -c "$runner" sh "$TIMEOUT_CMD" "${TIMEOUT_SEC}s" dotnet "$harness" "$input" </dev/null >"$output_file" 2>&1
    ec=$?
  else
    /bin/sh -c "$runner" sh dotnet "$harness" "$input" </dev/null >"$output_file" 2>&1
    ec=$?
  fi
  set -e
}

repro_crash_3of3() {
  local harness="$1"
  local input="$2"
  local sig=""

  for _ in 1 2 3; do
    local tmp
    tmp="$(mktemp)"
    run_dotnet_quiet "$harness" "$input" "$tmp"

    if [[ $ec -eq 0 || $ec -eq 124 ]]; then
      rm -f "$tmp"
      return 1
    fi

    local run_sig
    run_sig="$(signature_from_log "$tmp")"
    rm -f "$tmp"

    if [[ -z "$sig" ]]; then
      sig="$run_sig"
    elif [[ "$sig" != "$run_sig" ]]; then
      return 1
    fi
  done

  LAST_SIGNATURE="$sig"
  return 0
}

repro_hang_3of3() {
  local harness="$1"
  local input="$2"

  [[ -n "$TIMEOUT_CMD" ]] || return 1

  for _ in 1 2 3; do
    set +e
    /bin/sh -c '"$@"; rc=$?; exit "$rc"' sh "$TIMEOUT_CMD" "${TIMEOUT_SEC}s" dotnet "$harness" "$input" </dev/null >/dev/null 2>&1
    ec=$?
    set -e
    [[ $ec -eq 124 ]] || return 1
  done

  LAST_SIGNATURE="hang-timeout"
  return 0
}

append_manifest_entry() {
  local entry_json="$1"
  local tmp
  tmp="$(mktemp)"
  jq --argjson entry "$entry_json" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .updated_at_utc = $now
    | .entries = (.entries // [])
    | .entries += [$entry]
  ' "$MANIFEST" > "$tmp"
  mv "$tmp" "$MANIFEST"
}

copy_or_minimize() {
  local harness="$1"
  local source="$2"
  local destination="$3"

  mkdir -p "$(dirname "$destination")"

  if [[ $SKIP_MINIMIZE -eq 1 ]] || ! command -v afl-tmin >/dev/null 2>&1; then
    cp "$source" "$destination"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  set +e
  AFL_SKIP_BIN_CHECK=1 afl-tmin -i "$source" -o "$tmp" -m none -t "$((TIMEOUT_SEC * 1000))" -- dotnet "$harness" >/dev/null 2>&1
  local tmin_ec=$?
  set -e

  if [[ $tmin_ec -eq 0 && -s "$tmp" ]]; then
    mv "$tmp" "$destination"
  else
    rm -f "$tmp"
    cp "$source" "$destination"
  fi
}

REPRO_TOTAL=0
REPRO_SUCCESS=0
TRIAGE_TOTAL_SEC=0
NEW_FINDINGS=0

REPORT_DATE="$(date -u +%Y-%m-%d)"
REPORT_FILE="$FUZZ_ROOT/reports/fuzz-report-${REPORT_DATE}.md"

echo "[triage] start targets=$(IFS=,; echo "${TARGET_LIST[*]}") timeout_sec=$TIMEOUT_SEC minimize=$((1 - SKIP_MINIMIZE)) max_cases=$MAX_CASES"

for target in "${TARGET_LIST[@]}"; do
  TARGET_NEW_BEFORE="$NEW_FINDINGS"
  TRIAGE_RUN_DIR="$(create_run_dir "$target" "triage")"
  OUT_DIR="$TRIAGE_RUN_DIR/out"
  echo "[triage] target=$target phase=publish"
  publish_target "$target" "$OUT_DIR" "no"
  HARNESS="$OUT_DIR/$(assembly_for_target "$target").dll"
  echo "[triage] target=$target harness=$(basename "$HARNESS")"

  crash_total="$(find "$FUZZ_ROOT/artifacts/$target" -type f -path '*/findings/default/crashes/id:*' ! -path '*/triage/*' ! -path '*/replay/*' 2>/dev/null | wc -l | tr -d ' ')"
  hang_total="$(find "$FUZZ_ROOT/artifacts/$target" -type f -path '*/findings/default/hangs/id:*' ! -path '*/triage/*' ! -path '*/replay/*' 2>/dev/null | wc -l | tr -d ' ')"
  echo "[triage] target=$target candidates crashes=$crash_total hangs=$hang_total"

  TARGET_PROCESSED=0
  TARGET_CRASHES_PROCESSED=0
  TARGET_HANGS_PROCESSED=0

  while IFS= read -r crash_file; do
    if [[ $MAX_CASES -gt 0 && $TARGET_PROCESSED -ge $MAX_CASES ]]; then
      echo "[triage] target=$target limit_reached max_cases=$MAX_CASES"
      break
    fi

    REPRO_TOTAL=$((REPRO_TOTAL + 1))
    TARGET_PROCESSED=$((TARGET_PROCESSED + 1))
    TARGET_CRASHES_PROCESSED=$((TARGET_CRASHES_PROCESSED + 1))
    t0=$(date +%s)

    if repro_crash_3of3 "$HARNESS" "$crash_file"; then
      REPRO_SUCCESS=$((REPRO_SUCCESS + 1))
      sig_hash="$(printf '%s' "$LAST_SIGNATURE" | sha256sum | awk '{print $1}')"

      if ! hash_seen "$sig_hash"; then
        mark_hash_seen "$sig_hash"
        NEW_FINDINGS=$((NEW_FINDINGS + 1))
        short_hash="${sig_hash:0:12}"
        dest_rel="regressions/$target/open/${target}-$(date -u +%Y%m%d)-${short_hash}.bin"
        dest_abs="$FUZZ_ROOT/$dest_rel"
        copy_or_minimize "$HARNESS" "$crash_file" "$dest_abs"

        entry="$(jq -n \
          --arg id "${target}-${short_hash}" \
          --arg target "$target" \
          --arg input "$dest_rel" \
          --arg source "$(relative_path "$crash_file")" \
          --arg sig "$LAST_SIGNATURE" \
          --arg sig_hash "$sig_hash" \
          --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '{
            id: $id,
            target: $target,
            kind: "crash",
            status: "open",
            expectation: "crash",
            input_path: $input,
            source_artifact: $source,
            signature: $sig,
            signature_hash: $sig_hash,
            discovered_at_utc: $now,
            repro_3_of_3: true,
            notes: "Auto-triaged from local campaign artifacts."
          }')"
        append_manifest_entry "$entry"
        printf '| %s | crash | %s | 3/3 | %s |\n' "$target" "$short_hash" "$dest_rel" >> "$NEW_ROWS_FILE"
      fi
    fi

    t1=$(date +%s)
    TRIAGE_TOTAL_SEC=$((TRIAGE_TOTAL_SEC + (t1 - t0)))

    if [[ "$PROGRESS_EVERY" -gt 0 && $((TARGET_CRASHES_PROCESSED % PROGRESS_EVERY)) -eq 0 ]]; then
      echo "[triage] target=$target phase=crashes progress=${TARGET_CRASHES_PROCESSED}/${crash_total} repro_ok=${REPRO_SUCCESS}/${REPRO_TOTAL} new_findings=$NEW_FINDINGS"
    fi
  done < <(find "$FUZZ_ROOT/artifacts/$target" -type f -path '*/findings/default/crashes/id:*' ! -path '*/triage/*' ! -path '*/replay/*' 2>/dev/null | sort)

  while IFS= read -r hang_file; do
    if [[ $MAX_CASES -gt 0 && $TARGET_PROCESSED -ge $MAX_CASES ]]; then
      echo "[triage] target=$target limit_reached max_cases=$MAX_CASES"
      break
    fi

    REPRO_TOTAL=$((REPRO_TOTAL + 1))
    TARGET_PROCESSED=$((TARGET_PROCESSED + 1))
    TARGET_HANGS_PROCESSED=$((TARGET_HANGS_PROCESSED + 1))
    t0=$(date +%s)

    if repro_hang_3of3 "$HARNESS" "$hang_file"; then
      REPRO_SUCCESS=$((REPRO_SUCCESS + 1))
      sample_hash="$(sha256sum "$hang_file" | awk '{print $1}')"
      sig_hash="$(printf '%s|%s|%s' "$target" "$LAST_SIGNATURE" "$sample_hash" | sha256sum | awk '{print $1}')"

      if ! hash_seen "$sig_hash"; then
        mark_hash_seen "$sig_hash"
        NEW_FINDINGS=$((NEW_FINDINGS + 1))
        short_hash="${sig_hash:0:12}"
        dest_rel="regressions/$target/open/${target}-hang-$(date -u +%Y%m%d)-${short_hash}.bin"
        dest_abs="$FUZZ_ROOT/$dest_rel"
        cp "$hang_file" "$dest_abs"

        entry="$(jq -n \
          --arg id "${target}-hang-${short_hash}" \
          --arg target "$target" \
          --arg input "$dest_rel" \
          --arg source "$(relative_path "$hang_file")" \
          --arg sig "hang-timeout|$sample_hash" \
          --arg sig_hash "$sig_hash" \
          --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '{
            id: $id,
            target: $target,
            kind: "hang",
            status: "open",
            expectation: "hang",
            input_path: $input,
            source_artifact: $source,
            signature: $sig,
            signature_hash: $sig_hash,
            discovered_at_utc: $now,
            repro_3_of_3: true,
            notes: "Auto-triaged recurring timeout (hang)."
          }')"
        append_manifest_entry "$entry"
        printf '| %s | hang | %s | 3/3 timeout | %s |\n' "$target" "$short_hash" "$dest_rel" >> "$NEW_ROWS_FILE"
      fi
    fi

    t1=$(date +%s)
    TRIAGE_TOTAL_SEC=$((TRIAGE_TOTAL_SEC + (t1 - t0)))

    if [[ "$PROGRESS_EVERY" -gt 0 && $((TARGET_HANGS_PROCESSED % PROGRESS_EVERY)) -eq 0 ]]; then
      echo "[triage] target=$target phase=hangs progress=${TARGET_HANGS_PROCESSED}/${hang_total} repro_ok=${REPRO_SUCCESS}/${REPRO_TOTAL} new_findings=$NEW_FINDINGS"
    fi
  done < <(find "$FUZZ_ROOT/artifacts/$target" -type f -path '*/findings/default/hangs/id:*' ! -path '*/triage/*' ! -path '*/replay/*' 2>/dev/null | sort)

  if [[ $TARGET_CRASHES_PROCESSED -eq 0 && $crash_total -eq 0 ]]; then
    echo "[triage] target=$target phase=crashes status=none"
  fi
  if [[ $TARGET_HANGS_PROCESSED -eq 0 && $hang_total -eq 0 ]]; then
    echo "[triage] target=$target phase=hangs status=none"
  fi

  TARGET_NEW=$((NEW_FINDINGS - TARGET_NEW_BEFORE))
  echo "[triage] target=$target done processed=$TARGET_PROCESSED new_findings=$TARGET_NEW"
done

if [[ $REPRO_TOTAL -gt 0 ]]; then
  REPRO_RATE="$(awk -v ok="$REPRO_SUCCESS" -v total="$REPRO_TOTAL" 'BEGIN { printf "%.2f", (ok / total) * 100 }')"
  AVG_TRIAGE_SEC="$(awk -v sum="$TRIAGE_TOTAL_SEC" -v total="$REPRO_TOTAL" 'BEGIN { printf "%.2f", sum / total }')"
else
  REPRO_RATE="0.00"
  AVG_TRIAGE_SEC="0.00"
fi

{
  echo "# Fuzz Daily Report - $REPORT_DATE"
  echo
  echo "## Metrics"
  echo "- execs_done / execs_sec / paths_total / unique_crashes / unique_hangs:"
  for target in "${TARGET_LIST[@]}"; do
    latest="$(find "$FUZZ_ROOT/artifacts/$target" -maxdepth 1 -mindepth 1 -type d | sort | tail -n1 || true)"
    stats="${latest:-}/findings/default/fuzzer_stats"
    echo "  - $target: execs_done=$(stats_value "$stats" "execs_done") execs/sec=$(stats_value "$stats" "execs_per_sec") paths_total=$(stats_value "$stats" "paths_total") unique_crashes=$(stats_value "$stats" "unique_crashes") unique_hangs=$(stats_value "$stats" "unique_hangs")"
  done
  echo "- repro_3_of_3_rate: ${REPRO_RATE}% (${REPRO_SUCCESS}/${REPRO_TOTAL})"
  echo "- avg_triage_seconds: $AVG_TRIAGE_SEC"
  echo
  echo "## New Findings"
  echo "| Target | Kind | Signature Hash | Repro | Regression Input |"
  echo "|---|---|---|---|---|"
  if [[ -s "$NEW_ROWS_FILE" ]]; then
    cat "$NEW_ROWS_FILE"
  else
    echo "| - | - | - | - | none |"
  fi
} > "$REPORT_FILE"

echo "[triage] report=$(relative_path "$REPORT_FILE") new_findings=$NEW_FINDINGS repro_rate=${REPRO_RATE}% avg_triage_seconds=$AVG_TRIAGE_SEC"
