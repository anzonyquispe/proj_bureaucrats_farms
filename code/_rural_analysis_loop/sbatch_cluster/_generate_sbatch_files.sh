#!/bin/bash
# _generate_sbatch_files.sh
# Emit 16 SGE sbatch files (one Stata invocation per file) + 3 qsub launcher
# scripts for the rural analysis run on the cluster. Re-run any time the
# parameter plan changes.
#
# Plan (see CLAUDE.md requirement 6):
#   - location = shell (cluster)
#   - sample   = ""  (full data)
#   - is_rural_var: one sbatch per variant
#       is_rural_area   -> STER_SUFFIX="_area"
#       is_rural_farzad -> STER_SUFFIX="_farzad"
#   - Per-dofile FE grouping (heavy specs 23/25/29/32 spread across sets):
#       _app_18 (protest DiD)        : 1 group with all 32 FEs
#       _app_19 (polischar DiD)      : 1 group with all 32 FEs
#       _app_16 (polischar evst)     : 2 groups of 16 FEs
#           set1: 1..14 + 23 + 25
#           set2: 15..22, 24, 26..28, 30, 31 + 29 + 32
#       _app_17 (protest evst)       : 4 groups of 8 FEs
#           set1: 1..7 + 23
#           set2: 8..14 + 25
#           set3: 15..21 + 29
#           set4: 22, 24, 26..28, 30, 31 + 32
#   - Cores (#$ -pe smp):
#       protest   (_app_17, _app_18) -> 10
#       polischar (_app_16, _app_19) -> 5
#   - Total: 2 + 2 + 4 + 8 = 16 sbatch files. Every file runs exactly one
#     Stata job so all 16 can execute in parallel.
#   - Team workload split (16 total): Anzony 6, Ramiro 5, Mamoor 5.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
mkdir -p logs

# Clean stale files from any prior generator run.
rm -f "$HERE"/app*.sbatch "$HERE"/qsub_*.sh

# --- FE plan ------------------------------------------------------------------
FE_ALL="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32"

# _app_16 polischar event study: 2 sets of 16 FEs, 2 heavies each
FE_APP16_SET1="1 2 3 4 5 6 7 8 9 10 11 12 13 14 23 25"
FE_APP16_SET2="15 16 17 18 19 20 21 22 24 26 27 28 30 31 29 32"

# _app_17 protest event study: 4 sets of 8 FEs, 1 heavy each
FE_APP17_SET1="1 2 3 4 5 6 7 23"
FE_APP17_SET2="8 9 10 11 12 13 14 25"
FE_APP17_SET3="15 16 17 18 19 20 21 29"
FE_APP17_SET4="22 24 26 27 28 30 31 32"

emit_sbatch () {
    local job="$1" dofile="$2" cores="$3" fe_list="$4" \
          rural_var="$5" ster_suffix="$6"
    local out="${HERE}/${job}.sbatch"

    cat > "$out" <<SBATCH
#!/bin/bash
#\$ -M anzony.quispe@gmail.com
#\$ -m abe
#\$ -q largemem
#\$ -N ${job}
#\$ -pe smp ${cores}
#\$ -cwd
#\$ -o logs/\$JOB_NAME.\$JOB_ID.out
#\$ -e logs/\$JOB_NAME.\$JOB_ID.err

module load stata

# ---------- sbatch-array parameters ----------
LOCATION="shell"
SAMPLE=""
IS_RURAL_VAR="${rural_var}"
FE_LIST="${fe_list}"
STER_SUFFIX="${ster_suffix}"
DOFILE_NAME="${dofile}"
# ---------------------------------------------

# Cluster paths
# - PROJ_SHELL / PROJ_ROOT: the *data* root (shared group folder).
#   Stata sees it as \$root and loads every CSV/.dta from it.
# - GIT_ROOT: the *code* checkout for this repo on the cluster.
#   This is a per-user path and can differ from the data root.
PROJ_SHELL="/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
PROJ_ROOT="\$PROJ_SHELL"
GIT_ROOT="\${GIT_ROOT:-/users/aquisper/proj_bureaucrats_farms}"
DOFILE_PATH="\$GIT_ROOT/code/_rural_analysis_loop/\$DOFILE_NAME"
ADO_PATH="\$GIT_ROOT/code/_rural_analysis_loop/tools/estsave_csv.ado"

# SGE copies this script to a spool path before running it, so BASH_SOURCE
# resolves to the spool path rather than the submit dir. The #\$ -cwd
# directive already lands us in the submit dir, so we just use relative
# paths (./logs/...) which resolve against \$PWD == submit dir.
mkdir -p logs

WRAPPER="logs/${job}_wrapper.do"
cat > "\$WRAPPER" <<EOF
clear all
set more off
global location     "\$LOCATION"
global sample       "\$SAMPLE"
global is_rural_var "\$IS_RURAL_VAR"
global fe_list      "\$FE_LIST"
global ster_suffix  "\$STER_SUFFIX"
global shell        "\$PROJ_SHELL"
global dbox         ""
global root         "\$PROJ_ROOT"
qui do "\$ADO_PATH"
do "\$DOFILE_PATH"
EOF

echo "[\$(date '+%F %T')] starting ${job} (fe=\$FE_LIST, rural=\$IS_RURAL_VAR)"
stata-mp -b do "\$WRAPPER"
rc=\$?
echo "[\$(date '+%F %T')] ${job} finished rc=\$rc"
exit \$rc
SBATCH
    chmod +x "$out"
    echo "wrote $(basename "$out")"
}

# --- Generate the 16 sbatch files ---------------------------------------------

# _app_18 protest DiD: 1 set × 2 variants = 2 files
for v in area farzad; do
    rv="is_rural_$v"
    emit_sbatch "app18_${v}" "_app_18_protest_5km_did_downup_plot.do" 10 "$FE_ALL" "$rv" "_$v"
done

# _app_19 polischar DiD: 1 set × 2 variants = 2 files
for v in area farzad; do
    rv="is_rural_$v"
    emit_sbatch "app19_${v}" "_app_19_polischar_did_downup_inter_plot.do" 5 "$FE_ALL" "$rv" "_$v"
done

# _app_16 polischar event study: 2 sets × 2 variants = 4 files
for v in area farzad; do
    rv="is_rural_$v"
    emit_sbatch "app16_set1_${v}" "_app_16_polischar_evst_all.do" 5 "$FE_APP16_SET1" "$rv" "_$v"
    emit_sbatch "app16_set2_${v}" "_app_16_polischar_evst_all.do" 5 "$FE_APP16_SET2" "$rv" "_$v"
done

# _app_17 protest event study: 4 sets × 2 variants = 8 files
for v in area farzad; do
    rv="is_rural_$v"
    emit_sbatch "app17_set1_${v}" "_app_17_5km_evst_all.do" 10 "$FE_APP17_SET1" "$rv" "_$v"
    emit_sbatch "app17_set2_${v}" "_app_17_5km_evst_all.do" 10 "$FE_APP17_SET2" "$rv" "_$v"
    emit_sbatch "app17_set3_${v}" "_app_17_5km_evst_all.do" 10 "$FE_APP17_SET3" "$rv" "_$v"
    emit_sbatch "app17_set4_${v}" "_app_17_5km_evst_all.do" 10 "$FE_APP17_SET4" "$rv" "_$v"
done

# --- Team split (6 / 5 / 5) ---------------------------------------------------
# Cores per file: protest=10, polischar=5
#   Anzony (6 files, 60 cores): heaviest protest load + app18 both variants
#   Ramiro (5 files, 35 cores): protest set3 both + app16 set1 both + app19_area
#   Mamoor (5 files, 35 cores): protest set4 both + app16 set2 both + app19_farzad

ANZONY_FILES=(
    app17_set1_area.sbatch     app17_set1_farzad.sbatch
    app17_set2_area.sbatch     app17_set2_farzad.sbatch
    app18_area.sbatch          app18_farzad.sbatch
)
RAMIRO_FILES=(
    app17_set3_area.sbatch     app17_set3_farzad.sbatch
    app16_set1_area.sbatch     app16_set1_farzad.sbatch
    app19_area.sbatch
)
MAMOOR_FILES=(
    app17_set4_area.sbatch     app17_set4_farzad.sbatch
    app16_set2_area.sbatch     app16_set2_farzad.sbatch
    app19_farzad.sbatch
)

emit_qsub_launcher () {
    local owner="$1"; shift
    local files=("$@")
    local out="${HERE}/qsub_${owner}.sh"

    {
        echo '#!/bin/bash'
        echo "# qsub launcher -- ${owner}"
        echo '# Submit every sbatch file in this launcher to the cluster.'
        echo '# All jobs write output to Anzonys personal folder on the shared group space;'
        echo '# Ramiro and Mamoor must have read+write on that folder (ACL/umask configured).'
        echo
        echo 'set -euo pipefail'
        echo 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
        echo 'cd "$HERE"'
        echo 'mkdir -p logs'
        echo
        echo 'FILES=('
        for f in "${files[@]}"; do echo "    ${f}"; done
        echo ')'
        echo
        echo 'for sb in "${FILES[@]}"; do'
        echo '    if [[ ! -f "$sb" ]]; then'
        echo '        echo "MISSING: $sb" >&2; exit 1'
        echo '    fi'
        echo '    echo "qsub $sb"'
        echo '    qsub "$sb"'
        echo 'done'
        echo
        echo "echo \"${owner}: submitted \${#FILES[@]} jobs.\""
    } > "$out"
    chmod +x "$out"
    echo "wrote $(basename "$out")  (${#files[@]} jobs)"
}

emit_qsub_launcher anzony "${ANZONY_FILES[@]}"
emit_qsub_launcher ramiro "${RAMIRO_FILES[@]}"
emit_qsub_launcher mamoor "${MAMOOR_FILES[@]}"

echo
echo "Done. $(ls "${HERE}"/*.sbatch 2>/dev/null | wc -l | tr -d ' ') sbatch files and 3 launcher scripts generated."
