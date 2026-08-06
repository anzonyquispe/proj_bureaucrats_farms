#!/bin/bash

# ── CONFIG ──────────────────────────────────────────
FOLDER="."   # ← CHANGE THIS to your actual path
ARCHIVE="$FOLDER/_archive"
KEEP=50
# ────────────────────────────────────────────────────

mkdir -p "$ARCHIVE"

BEFORE=$(find "$FOLDER" -maxdepth 1 -type f | wc -l)
echo "Total files found: $BEFORE"
echo "Keeping newest  : $KEEP"
echo "Moving to archive: $((BEFORE - KEEP))"
echo ""

# -print0 and -0 handle filenames with spaces, quotes, special chars
find "$FOLDER" -maxdepth 1 -type f -printf "%T@ %p\0" | \
    sort -rn -z | \
    awk -v keep="$KEEP" 'BEGIN{RS="\0"; ORS="\0"} NR > keep {sub(/^[0-9.]+ /, ""); print}' | \
    xargs -0 -I {} mv {} "$ARCHIVE/"

AFTER=$(find "$FOLDER" -maxdepth 1 -type f | wc -l)
MOVED=$((BEFORE - AFTER))

echo "✔ Done!"
echo "  Files kept   : $AFTER"
echo "  Files moved  : $MOVED"
echo "  Archive folder: $ARCHIVE"