#!/usr/bin/env bash
# Copy job photos from old release priv trees into persistent var/static.
set -euo pipefail

ROOT="${1:-/home/henry/romp-crm}"
DEST="${JOB_PHOTO_STATIC_DIR:-$ROOT/var/static}"

mkdir -p "$DEST/uploads/job-photos"

shopt -s nullglob
for dir in "$ROOT"/_build/prod/rel/romp_crm/lib/romp_crm-*/priv/static/uploads/job-photos; do
  if [[ -d "$dir" ]]; then
    cp -an "$dir/." "$DEST/uploads/job-photos/" 2>/dev/null || cp -a "$dir/." "$DEST/uploads/job-photos/"
  fi
done

# Dev/test uploads under project priv (if any)
if [[ -d "$ROOT/priv/static/uploads/job-photos" ]]; then
  cp -an "$ROOT/priv/static/uploads/job-photos/." "$DEST/uploads/job-photos/" 2>/dev/null || \
    cp -a "$ROOT/priv/static/uploads/job-photos/." "$DEST/uploads/job-photos/"
fi

echo "Job photo files under: $DEST/uploads/job-photos"
find "$DEST/uploads/job-photos" -type f | wc -l | awk '{print "  file count: " $1}'
