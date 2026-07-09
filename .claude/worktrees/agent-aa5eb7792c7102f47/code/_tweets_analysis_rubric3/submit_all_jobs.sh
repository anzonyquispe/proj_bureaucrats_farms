#!/bin/bash
################################################################################
# submit_all_jobs.sh  (rubric_3)
# Submits all rubric_3 tweets-analysis sbatch files to the cluster.
# 1 core per job, 18 jobs total -- fully parallelizable.
################################################################################

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

mkdir -p logs

echo "=============================================="
echo "SUBMITTING ALL RUBRIC_3 TWEETS-ANALYSIS JOBS"
echo "Date: $(date)"
echo "=============================================="

count=0
for sb in sbatch/tweets_r3_*.sbatch; do
    [[ -f "$sb" ]] || continue
    echo "qsub $sb"
    qsub "$sb"
    count=$((count + 1))
done

echo ""
echo "=============================================="
echo "submitted $count jobs. Use 'qstat' to check status."
echo "=============================================="
