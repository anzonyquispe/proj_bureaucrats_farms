#!/bin/bash
# _generate_sbatch_files.sh
# Emit one SGE sbatch file per (prefix, suffix) pair (22 total) plus a
# single qsub launcher that submits them all. Each sbatch runs the shared
# _tweets_did_event_study.do once with $outcome_list set to that group's
# outcomes.
#
# Plan:
#   prefixes (11): n1 n2 n3 tw em rh pos neg neu mix unc
#   suffixes (2):  all own
#   total: 22 sbatch files, 1 core each, runnable concurrently.
#
# Re-run any time the outcome plan changes.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
mkdir -p logs

# Wipe stale generator output.
rm -f "$HERE"/tweets_*.sbatch "$HERE"/qsub_all_tweets.sh

# --- Outcome universes per rubric_1 categorical -----------------------------
TOPICS_PRIMARY="agriculture development election_campaign environment_pollution farmer_protest governance party_politics sports_culture tribute_ceremony unclear welfare"
TOPICS_SECONDARY="agriculture development election_campaign environment_pollution farmer_protest governance party_politics sports_culture tribute_ceremony welfare"
TOPICS_TERTIARY="accusatory agriculture development election_campaign environment_pollution farmer_protest governance party_politics sports_culture tribute_ceremony welfare"
TOPICS_NO_UNCLEAR="agriculture development election_campaign environment_pollution farmer_protest governance party_politics sports_culture tribute_ceremony welfare"
VALENCES="positive negative neutral mixed unclear"
RHET_MODES="accusatory celebratory ceremonial contempt critical empathetic fear_alarm governance grievance informational mobilizational persuasive reflective solidarity supportive tribute_ceremony unclear"

build_list () {
    local prefix="$1" suffix="$2"
    local items=""
    case "$prefix" in
        n1)                       items="$TOPICS_PRIMARY" ;;
        n2)                       items="$TOPICS_SECONDARY" ;;
        n3)                       items="$TOPICS_TERTIARY" ;;
        tw)                       items="$TOPICS_NO_UNCLEAR" ;;
        em)                       items="$VALENCES" ;;
        rh)                       items="$RHET_MODES" ;;
        pos|neg|neu|mix|unc)      items="$TOPICS_PRIMARY" ;;
        *) echo "unknown prefix: $prefix" >&2; exit 1 ;;
    esac
    local out=""
    for it in $items; do out="$out ${prefix}_${it}_${suffix}"; done
    echo "$out" | sed 's/^ *//'
}

emit_sbatch () {
    local prefix="$1" suffix="$2"
    local job="tweets_${prefix}_${suffix}"
    local outcomes; outcomes="$(build_list "$prefix" "$suffix")"
    local out="${HERE}/${job}.sbatch"

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

set -euo pipefail
module purge 2>/dev/null || true
module load stata

PROJ_SHELL="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
GIT_ROOT="\${GIT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
DOFILE_PATH="\$GIT_ROOT/code/_tweets_analysis/_tweets_did_event_study.do"

mkdir -p logs

# Per-job scratch dir so concurrent jobs don't share Stata temp state.
export TMPDIR="\${TMPDIR:-/tmp}/stata.\${JOB_ID:-\$\$}"
mkdir -p "\$TMPDIR"
trap 'rm -rf "\$TMPDIR"' EXIT

WRAPPER="logs/${job}_wrapper.do"
cat > "\$WRAPPER" <<EOF
clear all
set more off
global shell        "\$PROJ_SHELL"
global job_name     "${job}"
global outcome_list "${outcomes}"
do "\$DOFILE_PATH"
EOF

echo "[\$(date '+%F %T')] starting ${job}"
echo "  outcomes: ${outcomes}"
stata-mp -b do "\$WRAPPER"
rc=\$?
echo "[\$(date '+%F %T')] ${job} finished rc=\$rc"
exit \$rc
SBATCH
    chmod +x "$out"
    echo "wrote $(basename "$out")"
}

PREFIXES=(n1 n2 n3 tw em rh pos neg neu mix unc)
SUFFIXES=(all own)

for p in "${PREFIXES[@]}"; do
    for s in "${SUFFIXES[@]}"; do
        emit_sbatch "$p" "$s"
    done
done

# --- qsub launcher ----------------------------------------------------------
LAUNCHER="${HERE}/qsub_all_tweets.sh"
{
    echo '#!/bin/bash'
    echo '# Submit all tweets-analysis sbatch files to the cluster.'
    echo 'set -euo pipefail'
    echo 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
    echo 'cd "$HERE"'
    echo 'mkdir -p logs'
    echo
    echo 'count=0'
    echo 'for sb in tweets_*.sbatch; do'
    echo '    [[ -f "$sb" ]] || continue'
    echo '    echo "qsub $sb"'
    echo '    qsub "$sb"'
    echo '    count=$((count + 1))'
    echo 'done'
    echo
    echo 'echo "submitted $count tweets jobs."'
} > "$LAUNCHER"
chmod +x "$LAUNCHER"

echo
echo "Generated $(ls "${HERE}"/tweets_*.sbatch 2>/dev/null | wc -l | tr -d ' ') sbatch files + launcher."
