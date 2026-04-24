#!/bin/bash
# run_report.sh
# Full-variant end-to-end pipeline using the cluster .ster files:
#
#   Step 1  Stata  build_csvs.do            -> one CSV per (app16|app17, set, variant)
#   Step 2  R      build_event_study_plots  -> event-study PNGs
#   Step 3  Stata  build_interaction_plots  -> interaction PNGs (app18, app19)
#   Step 4  LaTeX  build_report_tex.sh      -> report_full.pdf
#
# Output: $PLOT_DIR/report/report_full.pdf
#
# Overridable env vars:
#   STATA_CMD : absolute path to Stata binary
#   DBOX      : Dropbox root
#   TABLES    : folder holding the .ster files

set -euo pipefail

PLOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PLOT_DIR"

STATA_CMD="${STATA_CMD:-/Applications/StataNow/StataMP.app/Contents/MacOS/StataMP}"
DBOX="${DBOX:-/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms}"
TABLES="${TABLES:-${DBOX}/tex/paper/tables}"

CSV_DIR="${PLOT_DIR}/intermediate_csv_full"
FIG_DIR="${PLOT_DIR}/figures_full"
LOG_DIR="${PLOT_DIR}/logs"
REPORT_DIR="${PLOT_DIR}/report"
mkdir -p "$CSV_DIR" "$FIG_DIR" "$LOG_DIR" "$REPORT_DIR"

FE_ALL="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32"

#-------------------------------------------------------------------------------
# Step 1/4  build all CSVs in a single Stata invocation
#-------------------------------------------------------------------------------

echo "==> Step 1/4  ster -> csv (build_csvs.do)"
WRAP_CSV="$LOG_DIR/build_csvs_wrapper.do"
cat > "$WRAP_CSV" <<EOF
global plot_dir "$PLOT_DIR"
global tables   "$TABLES"
global csv_dir  "$CSV_DIR"
do "$PLOT_DIR/build_csvs.do"
EOF
(
  cd "$LOG_DIR"
  "$STATA_CMD" -b -q do "$WRAP_CSV" >"$LOG_DIR/build_csvs.out" 2>&1
)
echo "    done."

#-------------------------------------------------------------------------------
# Step 2/4  event-study PNGs (R)
#-------------------------------------------------------------------------------

echo "==> Step 2/4  event-study PNGs (R)"
(
  cd "$LOG_DIR"
  PLOT_DIR="$PLOT_DIR" \
  FIG_DIR="$FIG_DIR" \
  CSV_DIR="$CSV_DIR" \
  Rscript "$PLOT_DIR/build_event_study_plots.R" \
      >"$LOG_DIR/build_event_study_plots.out" 2>&1
)
echo "    done."

#-------------------------------------------------------------------------------
# Step 3/4  interaction PNGs (Stata)
#-------------------------------------------------------------------------------

echo "==> Step 3/4  interaction PNGs (Stata)"
WRAP_INT="$LOG_DIR/build_interaction_plots_wrapper.do"
cat > "$WRAP_INT" <<EOF
global plot_dir "$PLOT_DIR"
global fig_dir  "$FIG_DIR"
global tables   "$TABLES"
global fe_all   "$FE_ALL"
do "$PLOT_DIR/build_interaction_plots.do"
EOF
(
  cd "$LOG_DIR"
  "$STATA_CMD" -b -q do "$WRAP_INT" >"$LOG_DIR/build_interaction_plots.out" 2>&1
)
echo "    done."

#-------------------------------------------------------------------------------
# Step 4/4  LaTeX -> PDF
#-------------------------------------------------------------------------------

echo "==> Step 4/4  LaTeX -> PDF"
TEX_PATH="$REPORT_DIR/report_full.tex"
PLOT_DIR="$PLOT_DIR" FIG_DIR="$FIG_DIR" TEX_PATH="$TEX_PATH" FE_ALL="$FE_ALL" \
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
