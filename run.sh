#!/usr/bin/env bash
# Launch OpenGate.
#   ./run.sh                 play (fullscreen; F11 toggles, Esc opens the menu)
#   ./run.sh --windowed      play in a window
#   ./run.sh -- --campaign=hollowmere --hero=kaelen --skip-intro    developer quick start (see src/dev/dev_tools.gd)
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "Godot 4 was not found. Install it (Arch/Omarchy: sudo pacman -S godot) or set GODOT=/path/to/godot." >&2
  exit 2
fi

MODE="--fullscreen"
ARGS=()
for a in "$@"; do
  if [ "$a" = "--windowed" ]; then MODE="--windowed"; else ARGS+=("$a"); fi
done

# First run (or after adding scripts): let Godot build its class cache.
if [ ! -d .godot ]; then
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
exec "$GODOT" --path . "$MODE" "${ARGS[@]}"
