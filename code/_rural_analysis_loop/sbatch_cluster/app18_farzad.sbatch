#!/bin/bash
#$ -N app18_farzad
#$ -S /bin/bash
#$ -cwd
#$ -o logs/$JOB_NAME.$JOB_ID.out
#$ -e logs/$JOB_NAME.$JOB_ID.err
#$ -pe smp 10
#$ -l h_vmem=8G
#$ -l h_rt=48:00:00

# ---------- sbatch-array parameters ----------
LOCATION="shell"
SAMPLE=""
IS_RURAL_VAR="is_rural_farzad"
FE_LIST="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32"
STER_SUFFIX="_farzad"
DOFILE_NAME="_app_18_protest_5km_did_downup_plot.do"
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

WRAPPER="$LOG_DIR/app18_farzad_wrapper.do"
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

echo "[$(date '+%F %T')] starting app18_farzad (fe=$FE_LIST, rural=$IS_RURAL_VAR)"
cd "$LOG_DIR"
"$STATA_CMD" -b -q do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] app18_farzad finished rc=$rc"
exit $rc
