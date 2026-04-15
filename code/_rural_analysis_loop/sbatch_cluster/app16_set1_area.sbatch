#!/bin/bash
#$ -N app16_set1_area
#$ -S /bin/bash
#$ -cwd
#$ -o logs/$JOB_NAME.$JOB_ID.out
#$ -e logs/$JOB_NAME.$JOB_ID.err
#$ -pe smp 5
#$ -l h_vmem=8G
#$ -l h_rt=48:00:00

# ---------- sbatch-array parameters ----------
LOCATION="shell"
SAMPLE=""
IS_RURAL_VAR="is_rural_area"
FE_LIST="1 2 3 4 5 6 7 8 9 10 11 12 13 14 23 25"
STER_SUFFIX="_area"
DOFILE_NAME="_app_16_polischar_evst_all.do"
# ---------------------------------------------

# Cluster paths (shared group folder)
PROJ_SHELL="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
PROJ_DBOX=""
PROJ_ROOT="$PROJ_SHELL"

# The .do files live in the git repo checkout under the shared project root.
# Override GIT_ROOT if your checkout lives elsewhere.
GIT_ROOT="${GIT_ROOT:-$PROJ_SHELL}"
DOFILE_PATH="$GIT_ROOT/code/_rural_analysis_loop/$DOFILE_NAME"

SBATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SBATCH_DIR/logs"
mkdir -p "$LOG_DIR"

STATA_CMD="${STATA_CMD:-stata-mp}"

WRAPPER="$LOG_DIR/app16_set1_area_wrapper.do"
cat > "$WRAPPER" <<EOF
clear all
set more off
global location     "$LOCATION"
global sample       "$SAMPLE"
global is_rural_var "$IS_RURAL_VAR"
global fe_list      "$FE_LIST"
global ster_suffix  "$STER_SUFFIX"
global shell        "$PROJ_SHELL"
global dbox         "$PROJ_DBOX"
global root         "$PROJ_ROOT"
qui do "\${root}/code/_replication_rural/estsave_csv.ado"
do "$DOFILE_PATH"
EOF

echo "[$(date '+%F %T')] starting app16_set1_area (fe=$FE_LIST, rural=$IS_RURAL_VAR)"
cd "$LOG_DIR"
"$STATA_CMD" -b -q do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] app16_set1_area finished rc=$rc"
exit $rc
