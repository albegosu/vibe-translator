#!/usr/bin/env bash
# Prints the release notes for a version: its CHANGELOG section plus install steps.
#
#   scripts/release-notes.sh 0.1.0
set -euo pipefail

VERSION="${1:?Usage: scripts/release-notes.sh <version>}"
cd "$(dirname "$0")/.."

SECTION="$(awk -v version="$VERSION" '
    index($0, "## [" version "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found && /^\[[^]]+\]: / { exit }
    found { print }
' CHANGELOG.md)"
if [[ -z "${SECTION//[[:space:]]/}" ]]; then
    echo "No CHANGELOG.md section for $VERSION" >&2
    exit 1
fi

printf '%s\n' "$SECTION"
cat <<'NOTES'

## Install

1. Download `VibeTranslator-*-macOS.zip`, unzip it and move **VibeTranslator.app** to `/Applications`.
2. Open it. The app isn't notarized yet, so macOS will block it the first time: go to *System Settings › Privacy & Security*, scroll down and click **Open Anyway** next to VibeTranslator.
3. Grant the **Accessibility** permission when asked, then follow [First run](https://github.com/albegosu/vibe-translator#first-run).

Requires macOS 26 or later. The `.sha256` file lets you verify the download with `shasum -a 256 -c`.
NOTES
