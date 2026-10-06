#!/usr/bin/env bash
# Turns a screen recording into the README demo GIF (docs/assets/demo.gif).
#
#   scripts/make-demo-gif.sh ~/Desktop/Screen\ Recording.mov
#   WIDTH=720 FPS=12 START=1.5 DURATION=14 scripts/make-demo-gif.sh recording.mov
#
# Record with ⌘⇧5 › "Record Selected Portion" around the Discord message box.
# Two-pass ffmpeg palette keeps text crisp and the file small.
set -euo pipefail

INPUT="${1:?Usage: scripts/make-demo-gif.sh <recording.mov> [output.gif]}"
[[ -f "$INPUT" ]] || { echo "Recording not found: $INPUT" >&2; exit 1; }
INPUT="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
if [[ -n "${2:-}" ]]; then
    OUTPUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
else
    OUTPUT="docs/assets/demo.gif"
fi
WIDTH="${WIDTH:-800}"
FPS="${FPS:-15}"
START="${START:-0}"
DURATION="${DURATION:-}"

command -v ffmpeg >/dev/null || { echo "ffmpeg is required: brew install ffmpeg" >&2; exit 1; }

cd "$(dirname "$0")/.."
mkdir -p "$(dirname "$OUTPUT")"

TRIM=(-ss "$START")
[[ -n "$DURATION" ]] && TRIM+=(-t "$DURATION")
FILTERS="fps=${FPS},scale=${WIDTH}:-1:flags=lanczos"
PALETTE="$(mktemp -t demo-palette).png"
trap 'rm -f "$PALETTE"' EXIT

ffmpeg -v error -y "${TRIM[@]}" -i "$INPUT" -vf "${FILTERS},palettegen=stats_mode=diff" "$PALETTE"
ffmpeg -v error -y "${TRIM[@]}" -i "$INPUT" -i "$PALETTE" \
    -lavfi "${FILTERS} [x]; [x][1:v] paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    -loop 0 "$OUTPUT"

SIZE_KB=$(( $(stat -f%z "$OUTPUT") / 1024 ))
echo "Wrote $OUTPUT (${SIZE_KB} KB)"
if (( SIZE_KB > 8192 )); then
    echo "Tip: over 8 MB loads slowly on GitHub. Try WIDTH=640, FPS=12 or a shorter DURATION." >&2
fi
