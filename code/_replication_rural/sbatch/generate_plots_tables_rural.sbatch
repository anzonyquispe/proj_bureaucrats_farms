#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N gen_plots_tables_rural
#$ -pe smp 4
#$ -cwd

#-------------------------------------------------------------------------------
# Generate all tables, event study plots, and interaction plots (RURAL)
# Runs: _generate_all_tables.do, plotting_event_studies.R, plotting_interaction.do
#-------------------------------------------------------------------------------

# Set root directory
ROOT="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
CODE_DIR="${ROOT}/code/_replication_rural"

# Change to code directory
cd "${CODE_DIR}"

echo "=========================================="
echo "Starting RURAL analysis pipeline"
echo "=========================================="

#-------------------------------------------------------------------------------
# Step 1: Generate all tables (Stata)
#-------------------------------------------------------------------------------
echo ""
echo "Step 1: Running _generate_all_tables.do..."
echo "----------------------------------------"
module load stata
stata-mp -b do _generate_all_tables.do
echo "Tables generated."

#-------------------------------------------------------------------------------
# Step 2: Plot event studies (R)
#-------------------------------------------------------------------------------
echo ""
echo "Step 2: Running plotting_event_studies.R..."
echo "----------------------------------------"
module load R
Rscript plotting_event_studies.R
echo "Event study plots generated."

#-------------------------------------------------------------------------------
# Step 3: Plot interactions (Stata)
#-------------------------------------------------------------------------------
echo ""
echo "Step 3: Running plotting_interaction.do..."
echo "----------------------------------------"
module load stata
stata-mp -b do plotting_interaction.do
echo "Interaction plots generated."

#-------------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "RURAL analysis pipeline complete!"
echo "=========================================="
