#!/usr/bin/env bash
# Prints the errors in an xcodebuild log as a GitHub annotation, minus anything that comes
# from Swift packages (the private Kero Engine and the cores it bundles).
# This repo is public, so its Actions logs are public too.
#
# Usage: ci/report-errors.sh <log file> <annotation title>
set -u

LOG="$1"
TITLE="$2"
[ -f "$LOG" ] || exit 0

ALL="$(grep -E "error:" "$LOG" | sort -u)"
[ -n "$ALL" ] || exit 0

SHOWN="$(printf '%s\n' "$ALL" | grep -vE "SourcePackages/|/checkouts/|Kero-Engine" | sed "s#${GITHUB_WORKSPACE:-$PWD}/##g" | head -40)"
HIDDEN=$(( $(printf '%s\n' "$ALL" | wc -l) - $(printf '%s' "$SHOWN" | grep -c '^' ) ))

if [ -n "$SHOWN" ]; then
  echo "::error title=$TITLE::$(printf '%s\n' "$SHOWN" | awk '{printf "%s%%0A", $0}')"
fi
if [ "$HIDDEN" -gt 0 ]; then
  echo "::error title=$TITLE (engine)::$HIDDEN error(s) in Kero Engine or its packages. Details are hidden in this public log; check Kero-Engine's CI or build locally."
fi
