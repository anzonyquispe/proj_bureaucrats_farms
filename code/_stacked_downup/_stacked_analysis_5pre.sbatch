#!/bin/bash
#$ -M anzony.quispe@gmail.com
#$ -m abe
#$ -q largemem
#$ -N _stacked_analysis_5pre
#$ -pe smp 4
#$ -cwd

set -euo pipefail

CODE_DIR="/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup"
cd "${CODE_DIR}"

echo "[$(date '+%F %T')] host=$(hostname) job=${JOB_ID:-NA} pwd=$(pwd)"
if command -v git >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] git HEAD: $(git -C "${CODE_DIR}" rev-parse --short HEAD 2>/dev/null || echo 'not-a-git-repo')"
fi

module purge 2>/dev/null || true
module load stata

export TMPDIR="${TMPDIR:-/tmp}/stata.${JOB_ID:-41877}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

rm -f "_stacked_analysis_5pre.log"
stata-mp -b do "_stacked_analysis_5pre.do"
