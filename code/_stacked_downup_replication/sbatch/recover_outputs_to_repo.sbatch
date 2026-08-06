#!/usr/bin/env bash
# Backward-compatible entry point. Run with bash on the login node.
set -euo pipefail

if [[ -n "${JOB_ID:-}" || -n "${SLURM_JOB_ID:-}" ]]; then
  echo "Do not submit this launcher with qsub/sbatch." >&2
  echo "Run: bash sbatch/submit_recovery_jobs.sh" >&2
  exit 64
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec bash "${SCRIPT_DIR}/submit_recovery_jobs.sh"
