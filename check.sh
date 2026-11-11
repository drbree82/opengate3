#!/usr/bin/env bash
# One command to verify the project after ANY change:
#   1. re-imports the project (rebuilds Godot's class cache so new class_name scripts are found)
#   2. compiles every script and lists parse errors with file + line number
#   3. runs every headless test in tests/ (rules, engine, campaign validation, campaign smoke test)
# Exit code 0 = everything passed.   Usage: ./check.sh              (everything)
#                                           ./check.sh test_rules   (only matching test files)
set -uo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "Godot 4 not found. Install it (e.g. 'sudo pacman -S godot') or set GODOT=/path/to/godot" >&2
  exit 2
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

echo "== 1/3 Importing project =="
"$GODOT" --headless --path . --import >"$LOG" 2>&1 || true

echo "== 2/3 Compiling scripts =="
"$GODOT" --headless --path . -s res://tools/parse_check.gd >"$LOG" 2>&1
STATUS=$?
grep -E "Parse Error|Compile Error|parse check|^   res://|^ +at: " "$LOG" | grep -vE "modules/gdscript|Failed to compile depended" | awk '!seen[$0]++' | head -n 60
if [ "$STATUS" -ne 0 ]; then
  echo "SCRIPT ERRORS: fix the first Parse Error above (later ones are often caused by it), then run ./check.sh again." >&2
  exit 1
fi

echo "== 3/3 Running tests =="
"$GODOT" --headless --path . -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$LOG" | grep -vE "^ok  |ObjectDB instances were leaked|resources still in use|at: (cleanup|clear) "
STATUS=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error" "$LOG"; then
  echo "SCRIPT ERRORS were reported during the tests (see above)." >&2
  STATUS=1
fi
if [ "$STATUS" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED" >&2; fi
exit "$STATUS"
