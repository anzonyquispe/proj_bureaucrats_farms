#!/bin/bash
#SBATCH --job-name=app19_test
#SBATCH --output=logs/app19_test_%j.out
#SBATCH --error=logs/app19_test_%j.err
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --cpus-per-task=4

# -------- sbatch-array parameters (one-off local test values) --------
LOCATION="dbox"
SAMPLE="_sample"
IS_RURAL_VAR="is_rural_area"
FE_LIST="1 8 16 24 32"
STER_SUFFIX="_test"
DOFILE_NAME="_app_19_polischar_did_downup_inter_plot.do"
# ---------------------------------------------------------------------

GIT_ROOT="/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms"
PROJ_SHELL="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
PROJ_DBOX="/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
if [[ "$LOCATION" == "dbox" ]]; then
    PROJ_ROOT="$PROJ_DBOX"
else
    PROJ_ROOT="$PROJ_SHELL"
fi

DOFILE_PATH="$GIT_ROOT/code/_rural_analysis_loop/$DOFILE_NAME"
SBATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SBATCH_DIR/logs"
mkdir -p "$LOG_DIR"

JOB_TAG="$(basename "$DOFILE_NAME" .do)${STER_SUFFIX}"
WRAPPER="$LOG_DIR/${JOB_TAG}_wrapper.do"
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

STATA_CMD="${STATA_CMD:-/Applications/StataNow/StataMP.app/Contents/MacOS/StataMP}"

cd "$LOG_DIR"
echo "[$(date '+%F %T')] starting $JOB_TAG (fe=$FE_LIST)"
"$STATA_CMD" -b -q do "$WRAPPER"
rc=$?
echo "[$(date '+%F %T')] $JOB_TAG finished rc=$rc"
exit $rc
