#!/bin/bash
# _generate_sbatch_files.sh  (rubric_3)
#
# Emit one SGE sbatch file per (prefix, suffix) pair (18 total) into ./sbatch/,
# plus submit_all_jobs.sh at the top level. Each sbatch runs the shared
# _tweets_did_event_study.do once with $outcome_list set to that group's
# outcomes. Mirrors the structure of code/_tweets_analysis/ and
# code/_tweets_analysis_rubric2/.
#
# Plan:
#   prefixes (9): cr pt bs sb pi pa ps cc ba    (rubric_3's 9 fields)
#   suffixes (2): all own
#   total: 18 sbatch files, 1 core each, runnable concurrently.
#
# Re-run any time the outcome plan changes; wipes prior generator output first.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SBATCH_DIR="$HERE/sbatch"
mkdir -p "$SBATCH_DIR" "$HERE/logs"

# Wipe stale generator output.
rm -f "$SBATCH_DIR"/tweets_*.sbatch "$HERE"/submit_all_jobs.sh

# --- Cluster paths (referenced inside each emitted sbatch) ------------------
CODE_DIR_REMOTE="/users/aquisper/proj_bureaucrats_farms/code/_tweets_analysis_rubric3"
PROJ_SHELL_REMOTE="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"

# --- Outcome universes per rubric_3 field -----------------------------------
NUMERIC_LEVELS="0 1 2 3"
POLLUTION_TYPE_VALS="crop_burning_smoke general_air_pollution industrial_pollution water_pollution other_environmental"
BOOL_VALS="true false"
STANCE_VALS="pro_enforcement anti_enforcement permissive neutral not_applicable"
PI_VALS="happy_seeder super_sms baler chc bio_decomposer biomass_plant straw_market satellite_monitoring fines_penalties caqm compensation_payment awareness_campaign machinery_subsidy other_instrument"
ACTION_VALS="subsidy_scheme enforcement_penalty infrastructure regulation awareness_campaign compensation other_policy"
STAGE_VALS="announcement implementation evaluation criticism demand"
BLAME_VALS="central_govt state_govt opposition farmers bureaucracy delhi_govt other"

build_list () {
    local prefix="$1" suffix="$2"
    local items=""
    local sep="_"
    case "$prefix" in
        cr)  items="$NUMERIC_LEVELS";        sep="" ;;
        pt)  items="$POLLUTION_TYPE_VALS" ;;
        bs)  items="$BOOL_VALS" ;;
        sb)  items="$STANCE_VALS" ;;
        pi)  items="$PI_VALS" ;;
        pa)  items="$ACTION_VALS" ;;
        ps)  items="$STAGE_VALS" ;;
        cc)  items="$BOOL_VALS" ;;
        ba)  items="$BLAME_VALS" ;;
        *) echo "unknown prefix: $prefix" >&2; exit 1 ;;
    esac
    local out=""
    for it in $items; do out="$out ${prefix}${sep}${it}_${suffix}"; done
    echo "$out" | sed 's/^ *//'
}

emit_sbatch () {
    local prefix="$1" suffix="$2"
    local job="tweets_r3_${prefix}_${suffix}"
    local outcomes; outcomes="$(build_list "$prefix" "$suffix")"
    local out="${SBATCH_DIR}/${job}.sbatch"

    cat > "$out" <<SBATCH
#!/bin/bash
#\$ -M anzony.quispe@gmail.com
#\$ -m abe
#\$ -q largemem
#\$ -N ${job}
#\$ -pe smp 1
#\$ -cwd
#\$ -o logs/\$JOB_NAME.\$JOB_ID.out
#\$ -e logs/\$JOB_NAME.\$JOB_ID.err

# -----------------------------------------------------------------------------
# Robustness preamble: fail loud, run the latest checked-out code, and start
# Stata from a clean module/temp environment so this job never picks up stale
# state from a prior submission. (Mirrors code/_replication_rural/sbatch/.)
# -----------------------------------------------------------------------------
set -euo pipefail

# Always run from the canonical project tree on the cluster -- guards against
# inheriting a stale CWD from the submitter's shell.
CODE_DIR="${CODE_DIR_REMOTE}"
cd "\${CODE_DIR}"

mkdir -p logs

echo "[\$(date '+%F %T')] host=\$(hostname) job=\${JOB_ID:-NA} pwd=\$(pwd)"
if command -v git >/dev/null 2>&1; then
    echo "[\$(date '+%F %T')] git HEAD: \$(git -C "\${CODE_DIR}" rev-parse --short HEAD 2>/dev/null || echo 'not-a-git-repo')"
fi

# Force a clean module environment then load stata fresh.
module purge 2>/dev/null || true
module load stata

# Per-job scratch dir so concurrent / repeat submissions don't share state.
export TMPDIR="\${TMPDIR:-/tmp}/stata.\${JOB_ID:-\$\$}"
mkdir -p "\${TMPDIR}"
trap 'rm -rf "\${TMPDIR}"' EXIT

# ---- Job-specific globals -> wrapper.do --------------------------------------
PROJ_SHELL="${PROJ_SHELL_REMOTE}"
DOFILE_PATH="\${CODE_DIR}/_tweets_did_event_study.do"
WRAPPER="logs/${job}_wrapper.do"

cat > "\${WRAPPER}" <<EOF
clear all
set more off
global shell        "\${PROJ_SHELL}"
global job_name     "${job}"
global outcome_list "${outcomes}"
do "\${DOFILE_PATH}"
EOF

# Wipe the prior Stata log for this wrapper so we read only this run's output.
rm -f "\${WRAPPER%.do}.log"

echo "[\$(date '+%F %T')] starting ${job}"
echo "  outcomes: ${outcomes}"
stata-mp -b do "\${WRAPPER}"
rc=\$?
echo "[\$(date '+%F %T')] ${job} finished rc=\$rc"
exit \$rc
SBATCH
    chmod +x "$out"
    echo "wrote sbatch/$(basename "$out")"
}

PREFIXES=(cr pt bs sb pi pa ps cc ba)
SUFFIXES=(all own)

for p in "${PREFIXES[@]}"; do
    for s in "${SUFFIXES[@]}"; do
        emit_sbatch "$p" "$s"
    done
done

# --- submit_all_jobs.sh ------------------------------------------------------
LAUNCHER="${HERE}/submit_all_jobs.sh"
cat > "$LAUNCHER" <<'LAUNCHER_EOF'
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
LAUNCHER_EOF
chmod +x "$LAUNCHER"

echo
echo "Generated $(ls "${SBATCH_DIR}"/tweets_r3_*.sbatch 2>/dev/null | wc -l | tr -d ' ') sbatch files in sbatch/ + submit_all_jobs.sh"
