#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUZZ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$FUZZ_ROOT"

PROJECT=""
INPUT_DIR=""
DICTIONARY=""
TIMEOUT_MS=10000
COMMAND="sharpfuzz"
OUTPUT_DIR="bin"
FINDINGS_DIR="findings"
INSTRUMENT_PATTERN='^NBitcoin\.dll$'
RESUME=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --input) INPUT_DIR="$2"; shift 2 ;;
    --dictionary) DICTIONARY="$2"; shift 2 ;;
    --timeout-ms) TIMEOUT_MS="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --findings-dir) FINDINGS_DIR="$2"; shift 2 ;;
    --instrument-pattern) INSTRUMENT_PATTERN="$2"; shift 2 ;;
    --resume) RESUME=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" || -z "$INPUT_DIR" ]]; then
  echo "Usage: $0 --project <csproj> --input <corpus-dir> [--dictionary <path>] [--timeout-ms <n>]" >&2
  exit 2
fi

if [[ ! -f "$PROJECT" ]]; then
  echo "Project not found: $PROJECT" >&2
  exit 2
fi

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Input directory not found: $INPUT_DIR" >&2
  exit 2
fi

if [[ -n "$DICTIONARY" && ! -f "$DICTIONARY" ]]; then
  echo "Dictionary not found: $DICTIONARY" >&2
  exit 2
fi

if [[ "$COMMAND" == */* ]]; then
  if [[ ! -x "$COMMAND" ]]; then
    echo "Instrumentation command is not executable: $COMMAND" >&2
    exit 2
  fi
elif ! command -v "$COMMAND" >/dev/null 2>&1; then
  echo "Instrumentation command not found in PATH: $COMMAND" >&2
  exit 2
fi

if [[ -d "$OUTPUT_DIR" ]]; then
  rm -rf "$OUTPUT_DIR"
fi

if [[ "$RESUME" -eq 0 && -d "$FINDINGS_DIR" ]]; then
  rm -rf "$FINDINGS_DIR"
fi

dotnet publish "$PROJECT" -c release -o "$OUTPUT_DIR"

project_name="$(basename "$PROJECT" .csproj)"
project_dll="${project_name}.dll"
project_path="${OUTPUT_DIR}/${project_dll}"

if [[ ! -f "$project_path" ]]; then
  echo "Published project DLL not found: $project_path" >&2
  exit 1
fi

exclude_dll() {
  local name="$1"
  case "$name" in
    dnlib.dll|SharpFuzz.dll|SharpFuzz.Common.dll|"${project_dll}") return 0 ;;
    System.*.dll) return 0 ;;
    *) return 1 ;;
  esac
}

echo "Instrumentation filter: $INSTRUMENT_PATTERN"
found_target=0
while IFS= read -r dll; do
  name="$(basename "$dll")"
  if exclude_dll "$name"; then
    continue
  fi

  if [[ ! "$name" =~ $INSTRUMENT_PATTERN ]]; then
    continue
  fi

  echo "Instrumenting $dll"
  "$COMMAND" "$dll"
  found_target=1
done < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.dll' | sort)

if [[ "$found_target" -eq 0 ]]; then
  echo "No fuzzing targets matched '$INSTRUMENT_PATTERN' in $OUTPUT_DIR" >&2
  exit 1
fi

export AFL_SKIP_BIN_CHECK=1
if [[ "$RESUME" -eq 1 && -f "$FINDINGS_DIR/default/fuzzer_stats" ]]; then
  export AFL_AUTORESUME=1
fi

input_for_afl="$INPUT_DIR"
if [[ "$RESUME" -eq 1 && -d "$FINDINGS_DIR/default/queue" ]]; then
  input_for_afl="-"
fi

if [[ -n "$DICTIONARY" ]]; then
  afl-fuzz -i "$input_for_afl" -o "$FINDINGS_DIR" -t "$TIMEOUT_MS" -m none -x "$DICTIONARY" -- dotnet "$project_path"
else
  afl-fuzz -i "$input_for_afl" -o "$FINDINGS_DIR" -t "$TIMEOUT_MS" -m none -- dotnet "$project_path"
fi
