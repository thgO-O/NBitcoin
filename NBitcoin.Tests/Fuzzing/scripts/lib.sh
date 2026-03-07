#!/usr/bin/env bash
set -euo pipefail

FUZZ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS=("psbt-transaction" "descriptor-miniscript" "block-message")

project_for_target() {
  case "$1" in
    psbt-transaction) echo "$FUZZ_ROOT/targets/NBitcoin.Fuzzing.PsbtTransaction/NBitcoin.Fuzzing.PsbtTransaction.csproj" ;;
    descriptor-miniscript) echo "$FUZZ_ROOT/targets/NBitcoin.Fuzzing.DescriptorMiniscript/NBitcoin.Fuzzing.DescriptorMiniscript.csproj" ;;
    block-message) echo "$FUZZ_ROOT/targets/NBitcoin.Fuzzing.BlockMessage/NBitcoin.Fuzzing.BlockMessage.csproj" ;;
    *) return 1 ;;
  esac
}

assembly_for_target() {
  case "$1" in
    psbt-transaction) echo "NBitcoin.Fuzzing.PsbtTransaction" ;;
    descriptor-miniscript) echo "NBitcoin.Fuzzing.DescriptorMiniscript" ;;
    block-message) echo "NBitcoin.Fuzzing.BlockMessage" ;;
    *) return 1 ;;
  esac
}

validate_target() {
  local target="$1"
  for t in "${TARGETS[@]}"; do
    if [[ "$t" == "$target" ]]; then
      return 0
    fi
  done
  echo "Unknown target: $target" >&2
  return 1
}

corpus_for_target() {
  echo "$FUZZ_ROOT/corpus/$1"
}

relative_path() {
  local path="$1"
  echo "${path#$FUZZ_ROOT/}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 2
  fi
}

optional_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 && command -v "$cmd"
}

timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    echo "timeout"
    return 0
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    echo "gtimeout"
    return 0
  fi
  return 1
}

create_run_dir() {
  local target="$1"
  local mode="$2"
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local dir="$FUZZ_ROOT/artifacts/$target/${ts}-${mode}"
  mkdir -p "$dir"
  ln -sfn "$(basename "$dir")" "$FUZZ_ROOT/artifacts/$target/latest"
  echo "$dir"
}

publish_target() {
  local target="$1"
  local out_dir="$2"
  local project
  project="$(project_for_target "$target")"

  mkdir -p "$out_dir"
  dotnet publish "$project" -c Release -o "$out_dir" >/dev/null
}

instrument_output_dir() {
  local target="$1"
  local out_dir="$2"
  local harness
  harness="$(assembly_for_target "$target").dll"

  require_cmd sharpfuzz

  local exclusions=(
    "dnlib.dll"
    "SharpFuzz.dll"
    "SharpFuzz.Common.dll"
    "$harness"
  )

  local found=0
  while IFS= read -r dll; do
    local name
    name="$(basename "$dll")"
    local skip=0

    for ex in "${exclusions[@]}"; do
      if [[ "$name" == "$ex" ]]; then
        skip=1
        break
      fi
    done
    if [[ "$skip" -eq 1 ]]; then
      continue
    fi
    if [[ "$name" == System.*.dll ]]; then
      continue
    fi

    sharpfuzz "$dll" >/dev/null
    found=1
  done < <(find "$out_dir" -maxdepth 1 -type f -name '*.dll' | sort)

  if [[ "$found" -eq 0 ]]; then
    echo "No fuzzing targets found in $out_dir" >&2
    return 1
  fi
}

stats_value() {
  local stats_file="$1"
  local key="$2"
  if [[ ! -f "$stats_file" ]]; then
    echo "0"
    return 0
  fi
  awk -F':' -v key="$key" '
    {
      field = $1
      gsub(/^[ \t]+|[ \t]+$/, "", field)
      if (field == key) {
        value = $2
        gsub(/^[ \t]+|[ \t]+$/, "", value)
        print value
      }
    }
  ' "$stats_file" | tail -n1
}
