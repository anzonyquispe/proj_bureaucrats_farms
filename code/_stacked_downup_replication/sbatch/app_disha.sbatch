#!/usr/bin/env bash
# DISHA appendix chain: build the AC-month panel, estimate, then describe.
#
# No mail directive here: SGE rejects -m without a matching -M, and hard-coding
# one address would send this job's mail to whoever committed the file. Ask for
# mail at submit time instead:
#   qsub -m abe -M you@example.edu app_disha.sbatch
#$ -N app_disha
#$ -q largemem
#$ -pe smp 1
#$ -cwd
#$ -o /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
#$ -e /users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication/logs
set -euo pipefail

DATA_ROOT="${REPLICATION_ROOT:-/groups/sgulzar/sa_fires/proj_bureaucrats_farms}"
CODE="${REPLICATION_CODE:-/users/aquisper/proj_bureaucrats_farms/code/_stacked_downup_replication}"
RUNNER="${CODE}/sbatch/run_dofile.sbatch"

# The three run in order: _app_disha_generation.do writes action_final.dta,
# which the other two read. Running them as one job keeps that dependency
# explicit instead of relying on submit order.
for DOFILE in _app_disha_generation.do _app_disha.do app_disha_desc.do; do
    echo "[$(date '+%F %T')] starting ${DOFILE}"
    bash "${RUNNER}" "${DOFILE}" "${DATA_ROOT}" "${CODE}" \
        shell none is_rural 1 none none none none
    echo "[$(date '+%F %T')] finished ${DOFILE}"
done

echo "[$(date '+%F %T')] DISHA appendix chain completed"
