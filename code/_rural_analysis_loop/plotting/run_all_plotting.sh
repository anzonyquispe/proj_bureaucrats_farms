#!/bin/bash
# run_all_plotting.sh
# End-to-end pipeline: STER -> CSV -> event-study PNGs + interaction PNGs
# -> LaTeX -> PDF report.
#
# Defaults match the local sbatch test run (sample=_sample, suffix=_test,
# fe grid = 1 8 16 24 32). Override via env vars before calling:
#   SAMPLE=_sample STER_SUFFIX=_test FE_LABELS="1 8 16 24 32" ./run_all_plotting.sh

set -euo pipefail

PLOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PLOT_DIR"

SAMPLE="${SAMPLE:-_sample}"
STER_SUFFIX="${STER_SUFFIX:-_test}"
FE_LABELS="${FE_LABELS:-1 8 16 24 32}"
STATA_CMD="${STATA_CMD:-/Applications/StataNow/StataMP.app/Contents/MacOS/StataMP}"

DBOX="/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
TABLES="${DBOX}/tex/paper/tables"

CSV_DIR="$PLOT_DIR/intermediate_csv"
FIG_DIR="$PLOT_DIR/figures"
LOG_DIR="$PLOT_DIR/logs"
REPORT_DIR="$PLOT_DIR/report"
mkdir -p "$CSV_DIR" "$FIG_DIR" "$LOG_DIR" "$REPORT_DIR"

NAMES=(
  "_app_16_polischar_evst_all"
  "_app_17_5km_evst_all"
  "_app_18_protest_5km_did_downup_plot"
  "_app_19_polischar_did_downup_inter_plot"
)

ster_of() { echo "${TABLES}/${1}${SAMPLE}_rural${STER_SUFFIX}.ster"; }
csv_of()  { echo "${CSV_DIR}/${1}${SAMPLE}_rural${STER_SUFFIX}.csv"; }

echo "==> Step 1/4  ster -> csv (parallel)"
pids=()
for n in "${NAMES[@]}"; do
    ster="$(ster_of "$n")"
    csv="$(csv_of "$n")"
    if [[ ! -f "$ster" ]]; then
        echo "    MISSING: $ster"
        continue
    fi
    (
      wrap="$LOG_DIR/ster2csv_${n}.do"
      cat > "$wrap" <<EOF
global ster_path "$ster"
global csv_path  "$csv"
global plot_dir  "$PLOT_DIR"
do "$PLOT_DIR/ster_to_csv.do"
EOF
      cd "$LOG_DIR"
      "$STATA_CMD" -b -q do "$wrap" >"$LOG_DIR/ster2csv_${n}.out" 2>&1
    ) &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
echo "    done."

echo "==> Step 2/4  event-study PNGs (R)"
(
  cd "$LOG_DIR"
  PLOT_DIR="$PLOT_DIR" \
  FIG_DIR="$FIG_DIR" \
  CSV_APP16="$(csv_of "${NAMES[0]}")" \
  CSV_APP17="$(csv_of "${NAMES[1]}")" \
  FE_LABELS="$FE_LABELS" \
  Rscript "$PLOT_DIR/build_event_study_plots.R" \
      >"$LOG_DIR/build_event_study_plots.out" 2>&1
)
echo "    done."

echo "==> Step 3/4  interaction PNGs (Stata)"
(
  wrap="$LOG_DIR/build_interaction_plots_wrapper.do"
  cat > "$wrap" <<EOF
global plot_dir   "$PLOT_DIR"
global fig_dir    "$FIG_DIR"
global ster_app18 "$(ster_of "${NAMES[2]}")"
global ster_app19 "$(ster_of "${NAMES[3]}")"
global fe_labels  "$FE_LABELS"
do "$PLOT_DIR/build_interaction_plots.do"
EOF
  cd "$LOG_DIR"
  "$STATA_CMD" -b -q do "$wrap" >"$LOG_DIR/build_interaction_plots.out" 2>&1
)
echo "    done."

echo "==> Step 4/4  LaTeX -> PDF"
TEX_PATH="$REPORT_DIR/report${STER_SUFFIX}.tex"
PLOT_DIR="$PLOT_DIR" FIG_DIR="$FIG_DIR" TEX_PATH="$TEX_PATH" FE_LABELS="$FE_LABELS" \
    bash "$PLOT_DIR/build_report_tex.sh"

(
    cd "$REPORT_DIR"
    pdflatex -interaction=nonstopmode -halt-on-error "$(basename "$TEX_PATH")" \
        >"$LOG_DIR/pdflatex_pass1.out" 2>&1 || true
    pdflatex -interaction=nonstopmode -halt-on-error "$(basename "$TEX_PATH")" \
        >"$LOG_DIR/pdflatex_pass2.out" 2>&1
)

PDF_PATH="${TEX_PATH%.tex}.pdf"
if [[ -f "$PDF_PATH" ]]; then
    echo "PDF: $PDF_PATH"
else
    echo "ERROR: PDF not produced. See $LOG_DIR/pdflatex_pass2.out" >&2
    exit 1
fi
