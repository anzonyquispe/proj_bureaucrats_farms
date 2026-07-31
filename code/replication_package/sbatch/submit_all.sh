#!/usr/bin/env bash
set -euo pipefail

array_job=$(sbatch --parsable sbatch/analysis_array.sbatch)
post_job=$(sbatch --parsable --dependency="afterok:${array_job}" sbatch/postprocess.sbatch)
echo "Analysis array job: ${array_job}"
echo "Dependent post-processing job: ${post_job}"

