#!/bin/bash

# ── CONFIG ──────────────────────────────────────────
FOLDER="."                    # change to your folder path
ARCHIVE="$FOLDER/_archive"
KEEP=50
# ────────────────────────────────────────────────────

# Create _archive folder if it doesn't exist
mkdir -p "$ARCHIVE"

# Get all files sorted by newest first (excluding _archive folder)
FILES=($(find "$FOLDER" -maxdepth 1 -type f | xargs ls -t 2>/dev/null))

TOTAL=${#FILES[@]}
echo "Total files found: $TOTAL"
echo "Keeping newest  : $KEEP"
echo "Moving to archive: $((TOTAL - KEEP))"
echo ""

# Move all files AFTER the first 50 to _archive
for ((i=KEEP; i<TOTAL; i++)); do
    echo "  → Moving: ${FILES[$i]}"
    mv "${FILES[$i]}" "$ARCHIVE/"
done

echo ""
echo "✔ Done. _archive now contains $((TOTAL - KEEP)) archived files."
