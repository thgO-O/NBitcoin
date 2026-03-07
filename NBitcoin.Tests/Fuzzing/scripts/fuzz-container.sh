#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUZZ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FUZZ_ROOT/../.." && pwd)"

DOCKER_BIN="${DOCKER_BIN:-docker}"
IMAGE="${FUZZ_IMAGE:-nbitcoin-fuzz:local}"
REBUILD=0
USE_STATE_VOLUME=1
STATE_VOLUME=""

PROJECT=""
INPUT_DIR=""
DICTIONARY=""
TIMEOUT_MS=10000
COMMAND="/opt/tools/sharpfuzz"
OUTPUT_DIR="bin"
FINDINGS_DIR=""
FINDINGS_DIR_SET=0
INSTRUMENT_PATTERN='^NBitcoin\.dll$'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --input) INPUT_DIR="$2"; shift 2 ;;
    --dictionary) DICTIONARY="$2"; shift 2 ;;
    --timeout-ms) TIMEOUT_MS="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --findings-dir) FINDINGS_DIR="$2"; FINDINGS_DIR_SET=1; shift 2 ;;
    --instrument-pattern) INSTRUMENT_PATTERN="$2"; shift 2 ;;
    --state-volume) STATE_VOLUME="$2"; USE_STATE_VOLUME=1; shift 2 ;;
    --no-state-volume) USE_STATE_VOLUME=0; shift ;;
    --ephemeral) USE_STATE_VOLUME=0; shift ;;
    --image) IMAGE="$2"; shift 2 ;;
    --rebuild) REBUILD=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" || -z "$INPUT_DIR" ]]; then
  echo "Usage: $0 --project <csproj> --input <corpus-dir> [--dictionary <path>] [--timeout-ms <n>] [--state-volume <name>|--no-state-volume] [--rebuild]" >&2
  exit 2
fi

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
  echo "Docker binary not found: $DOCKER_BIN" >&2
  exit 2
fi

to_container_path() {
  local path="$1"
  local abs
  if [[ "$path" == /* ]]; then
    abs="$path"
  else
    local base dir
    base="$(basename "$path")"
    dir="$(dirname "$path")"
    abs="$(cd "$FUZZ_ROOT" && cd "$dir" && printf '%s/%s' "$(pwd -P)" "$base")"
  fi

  if [[ "$abs" != "$REPO_ROOT/"* ]]; then
    echo "Path must be inside repo root: $path -> $abs" >&2
    return 1
  fi

  echo "/work/${abs#$REPO_ROOT/}"
}

target_name_from_project() {
  local project_path="$1"
  local base
  base="$(basename "$project_path")"
  case "$base" in
    NBitcoin.Fuzzing.PsbtTransaction.csproj) echo "psbt-transaction" ;;
    NBitcoin.Fuzzing.DescriptorMiniscript.csproj) echo "descriptor-miniscript" ;;
    NBitcoin.Fuzzing.BlockMessage.csproj) echo "block-message" ;;
    *)
      local input_base
      input_base="$(basename "$INPUT_DIR")"
      if [[ -n "$input_base" ]]; then
        echo "$input_base"
      else
        echo "custom"
      fi
      ;;
  esac
}

copy_if_exists() {
  local cid="$1"
  local src="$2"
  local dst="$3"
  mkdir -p "$(dirname "$dst")"
  "$DOCKER_BIN" cp "${cid}:${src}" "$dst" >/dev/null 2>&1 || true
}

export_findings_subset() {
  local cid="$1"
  local container_findings="$2"
  local host_findings="$3"

  rm -rf "$host_findings"
  mkdir -p "$host_findings/default"

  copy_if_exists "$cid" "$container_findings/default/fuzzer_stats" "$host_findings/default/fuzzer_stats"
  copy_if_exists "$cid" "$container_findings/default/plot_data" "$host_findings/default/plot_data"
  copy_if_exists "$cid" "$container_findings/default/cmdline" "$host_findings/default/cmdline"
  copy_if_exists "$cid" "$container_findings/default/crashes" "$host_findings/default/"
  copy_if_exists "$cid" "$container_findings/default/hangs" "$host_findings/default/"
}

TARGET_NAME="$(target_name_from_project "$PROJECT")"
if [[ "$FINDINGS_DIR_SET" -eq 0 ]]; then
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-container"
  FINDINGS_DIR="artifacts/$TARGET_NAME/$RUN_ID/findings"
fi

if [[ "$FINDINGS_DIR" == /* ]]; then
  HOST_FINDINGS_ABS="$FINDINGS_DIR"
else
  HOST_FINDINGS_ABS="$FUZZ_ROOT/$FINDINGS_DIR"
fi

if [[ -z "$STATE_VOLUME" && "$USE_STATE_VOLUME" -eq 1 ]]; then
  STATE_VOLUME="nbitcoin-afl-state-$TARGET_NAME"
fi

echo "Findings directory: $FINDINGS_DIR"
if [[ "$USE_STATE_VOLUME" -eq 1 ]]; then
  echo "Mode: hybrid (state volume + selective export)"
  echo "State volume: $STATE_VOLUME"
else
  echo "Mode: ephemeral (no persistent queue; selective export only)"
fi

PROJECT_C="$(to_container_path "$PROJECT")"
INPUT_DIR_C="$(to_container_path "$INPUT_DIR")"
if [[ -n "$DICTIONARY" ]]; then
  DICTIONARY_C="$(to_container_path "$DICTIONARY")"
else
  DICTIONARY_C=""
fi

CONTAINER_FINDINGS_DIR="/tmp/nbitcoin-findings"
if [[ "$USE_STATE_VOLUME" -eq 1 ]]; then
  CONTAINER_FINDINGS_DIR="/state/findings"
fi

mkdir -p "$(dirname "$HOST_FINDINGS_ABS")"

if [[ "$REBUILD" -eq 1 ]]; then
  "$DOCKER_BIN" build -f "$FUZZ_ROOT/Dockerfile.fuzz" -t "$IMAGE" "$REPO_ROOT"
else
  if ! "$DOCKER_BIN" image inspect "$IMAGE" >/dev/null 2>&1; then
    "$DOCKER_BIN" build -f "$FUZZ_ROOT/Dockerfile.fuzz" -t "$IMAGE" "$REPO_ROOT"
  fi
fi

docker_args=(-v "$REPO_ROOT:/work" -w /work/NBitcoin.Tests/Fuzzing)
if [[ "$USE_STATE_VOLUME" -eq 1 ]]; then
  docker_args+=(-v "$STATE_VOLUME:/state")
fi
for env_name in AFL_BENCH_JUST_ONE AFL_EXIT_WHEN_DONE; do
  if [[ -n "${!env_name:-}" ]]; then
    docker_args+=(-e "$env_name=${!env_name}")
  fi
done
if [[ -t 0 && -t 1 ]]; then
  docker_args=(-it "${docker_args[@]}")
fi

inner_args=(
  ./scripts/fuzz-inner.sh
  --project "$PROJECT_C"
  --input "$INPUT_DIR_C"
  --timeout-ms "$TIMEOUT_MS"
  --command "$COMMAND"
  --output-dir "$OUTPUT_DIR"
  --findings-dir "$CONTAINER_FINDINGS_DIR"
  --instrument-pattern "$INSTRUMENT_PATTERN"
)
if [[ "$USE_STATE_VOLUME" -eq 1 ]]; then
  inner_args+=(--resume)
fi
if [[ -n "$DICTIONARY_C" ]]; then
  inner_args+=(--dictionary "$DICTIONARY_C")
fi

cid="$($DOCKER_BIN create "${docker_args[@]}" "$IMAGE" "${inner_args[@]}")"
set +e
"$DOCKER_BIN" start -a "$cid"
run_ec=$?
set -e

export_findings_subset "$cid" "$CONTAINER_FINDINGS_DIR" "$HOST_FINDINGS_ABS"
"$DOCKER_BIN" rm -f "$cid" >/dev/null 2>&1 || true

exit "$run_ec"
