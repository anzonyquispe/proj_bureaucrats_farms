#!/bin/bash
# Run all four analysis sbatch scripts on this Mac in parallel.
# Each child writes its own Stata log under logs/; this launcher also captures
# stdout/stderr per job for the bash-level messages.
set -u

SBATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SBATCH_DIR"
mkdir -p logs

JOBS=(run_app16.sbatch run_app17.sbatch run_app18.sbatch run_app19.sbatch)

PIDS=()
for sb in "${JOBS[@]}"; do
    tag="${sb%.sbatch}"
    echo "Launching $sb ..."
    bash "$sb" >"logs/${tag}_launcher.stdout" 2>"logs/${tag}_launcher.stderr" &
    PIDS+=($!)
done

echo "PIDs: ${PIDS[*]}"
echo "Waiting for ${#JOBS[@]} jobs to complete..."

fail=0
for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    sb="${JOBS[$i]}"
    if wait "$pid"; then
        echo "[OK]  $sb (pid $pid)"
    else
        rc=$?
        echo "[ERR] $sb (pid $pid) exited $rc"
        fail=$((fail+1))
    fi
done

if [[ $fail -eq 0 ]]; then
    echo "All ${#JOBS[@]} jobs completed successfully."
else
    echo "$fail job(s) failed. Inspect logs/ for per-job Stata .log and launcher .stderr files."
fi
exit $fail
