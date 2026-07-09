#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N app19_area
#$ -pe smp 5
#$ -cwd
#$ -o logs/$JOB_NAME.$JOB_ID.out
#$ -e logs/$JOB_NAME.$JOB_ID.err

module load stata

# ---------- sbatch-array parameters ----------
LOCATION="shell"
SAMPLE=""
IS_RURAL_VAR="is_rural_area"
FE_LIST="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32"
STER_SUFFIX="_area"
DOFILE_NAME="_app_19_polischar_did_downup_inter_plot.do"
# ---------------------------------------------

# Cluster paths
# - PROJ_SHELL / PROJ_ROOT: the *data* root (shared group folder).
#   Stata sees it as $root and loads every CSV/.dta from it.
# - GIT_ROOT: the *code* checkout for this repo on the cluster.
#   This is a per-user path and can differ from the data root.
PROJ_SHELL="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
PROJ_ROOT="$PROJ_SHELL"
GIT_ROOT="${GIT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
DOFILE_PATH="$GIT_ROOT/code/_rural_analysis_loop/$DOFILE_NAME"
ADO_PATH="$GIT_ROOT/code/_rural_analysis_loop/tools/estsave_csv.ado"

# SGE copies this script to a spool path before running it, so BASH_SOURCE
# resolves to the spool path rather than the submit dir. The #$ -cwd
# directive already lands us in the submit dir, so we just use relative
# paths (./logs/...) which resolve against $PWD == submit dir.
mkdir -p logs

WRAPPER="logs/app19_area_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global location     "$LOCATION"
global sample       "$SAMPLE"
global is_rural_var "$IS_RURAL_VAR"
global fe_list      "$FE_LIST"
global ster_suffix  "$STER_SUFFIX"
global shell        "$PROJ_SHELL"
global dbox         ""
global root         "$PROJ_ROOT"
qui do "$ADO_PATH"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting app19_area (fe=$FE_LIST, rural=$IS_RURAL_VAR)"
stata-mp -b do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] app19_area finished rc=$rc"
exit $rc
