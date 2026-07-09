#!/bin/bash
#-------------------------------------------------------------------------------
# Generate all tables, event study plots, and interaction plots (RURAL)
# Run locally on macOS
#-------------------------------------------------------------------------------

# Set root directory
ROOT="/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_replication_rural"

# Stata path on macOS
STATA="/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp"

cd "${CODE_DIR}"

echo "=========================================="
echo "Starting RURAL analysis pipeline"
echo "=========================================="

# Step 1: Generate all tables (Stata)
echo ""
echo "Step 1: Running _generate_all_tables.do..."
echo "----------------------------------------"
"$STATA" -b do _generate_all_tables.do

# Step 2: Plot event studies (R)
echo ""
echo "Step 2: Running plotting_event_studies.R..."
echo "----------------------------------------"
Rscript plotting_event_studies.R

# Step 3: Plot interactions (Stata)
echo ""
echo "Step 3: Running plotting_interaction.do..."
echo "----------------------------------------"
"$STATA" -b do plotting_interaction.do

echo ""
echo "=========================================="
echo "RURAL analysis pipeline complete!"
echo "=========================================="
