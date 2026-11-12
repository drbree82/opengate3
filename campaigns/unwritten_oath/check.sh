#!/usr/bin/env bash
# Run from any directory; no engine modification or network access.
set -euo pipefail
cd "$(dirname "$0")/../.."
./check.sh
log=$(mktemp)
trap 'rm -f "$log"' EXIT
"${GODOT:-godot}" --headless --path . -s res://campaigns/unwritten_oath/tests/run.gd >"$log" 2>&1
cat "$log"
if grep -qE 'SCRIPT ERROR|Parse Error|FAIL' "$log"; then exit 1; fi
