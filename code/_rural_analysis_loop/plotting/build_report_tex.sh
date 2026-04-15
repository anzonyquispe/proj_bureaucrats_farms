#!/bin/bash
# build_report_tex.sh
# Generate a self-contained LaTeX file that collects every PNG produced by the
# event-study and interaction builders into a single PDF report.
#
# Required env vars:
#   PLOT_DIR   : absolute path to this plotting/ folder
#   FIG_DIR    : absolute path to the figures dir where PNGs live
#   TEX_PATH   : absolute path of the .tex file to write (e.g. $PLOT_DIR/report.tex)
#   FE_LABELS  : space-separated FE indices corresponding to each evregK slot

set -u
: "${PLOT_DIR:?}"; : "${FIG_DIR:?}"; : "${TEX_PATH:?}"; : "${FE_LABELS:?}"

read -r -a FE_ARR <<< "$FE_LABELS"

fig_rel() {
    # Path of figure relative to TEX_PATH's directory.
    python3 - <<PY
import os, sys
print(os.path.relpath("$FIG_DIR/$1", start=os.path.dirname("$TEX_PATH")))
PY
}

emit_figure() {
    local path="$1" caption="$2"
    if [[ ! -f "$FIG_DIR/$path" ]]; then
        echo "% MISSING: $path" >> "$TEX_PATH"
        return
    fi
    local rel; rel="$(fig_rel "$path")"
    cat >> "$TEX_PATH" <<EOF
\\begin{figure}[H]
\\centering
\\includegraphics[width=0.85\\linewidth]{${rel}}
\\caption{${caption}}
\\end{figure}
EOF
}

mkdir -p "$(dirname "$TEX_PATH")"
cat > "$TEX_PATH" <<'HEADER'
\documentclass[11pt]{article}
\usepackage[margin=1in]{geometry}
\usepackage{graphicx}
\usepackage{float}
\usepackage{caption}
\usepackage{hyperref}
\usepackage{placeins}

\title{Rural Analysis --- FE Selection Report\\\large (sample = \_sample, suffix = \_test)}
\author{proj\_bureaucrats\_farms}
\date{\today}

\begin{document}
\maketitle

\noindent
This report collects the event-study and interaction plots generated from
the sbatch test run over fixed-effects specifications
\texttt{\{1, 8, 16, 24, 32\}} on the \texttt{\_sample} subset, rural grids
(\texttt{is\_rural\_area}). For every FE spec, the event-study builder
produces an original panel and a linear-detrended (``rotated'') panel. The
interaction builder produces one lincom plot per FE spec for each of the
two triple-interaction DiD regressions.

\tableofcontents
\clearpage

\section{Event studies --- Politician characteristics (\texttt{\_app\_16})}
Dependent variable: fires per 1{,}000 units. Base event period: $t = -1$.
HEADER

for i in "${!FE_ARR[@]}"; do
    fe="${FE_ARR[$i]}"
    slot=$((i + 1))
    cat >> "$TEX_PATH" <<EOF
\\subsection*{FE specification \\texttt{fe${fe}} (slot \`evreg${slot}')}
EOF
    emit_figure "app16_polischar_evst_fe${fe}_ori.png"      "Event study, original (fe${fe})"
    emit_figure "app16_polischar_evst_fe${fe}_rotated.png"  "Event study, linear-detrended (fe${fe})"
done
echo "\\FloatBarrier" >> "$TEX_PATH"

cat >> "$TEX_PATH" <<'HEADER'
\clearpage
\section{Event studies --- Protest (\texttt{\_app\_17})}
Dependent variable: fires per 1{,}000 units. Base event period: $t = 0$.
HEADER

for i in "${!FE_ARR[@]}"; do
    fe="${FE_ARR[$i]}"
    slot=$((i + 1))
    cat >> "$TEX_PATH" <<EOF
\\subsection*{FE specification \\texttt{fe${fe}} (slot \`evreg${slot}')}
EOF
    emit_figure "app17_protest_evst_fe${fe}_ori.png"      "Event study, original (fe${fe})"
    emit_figure "app17_protest_evst_fe${fe}_rotated.png"  "Event study, linear-detrended (fe${fe})"
done
echo "\\FloatBarrier" >> "$TEX_PATH"

cat >> "$TEX_PATH" <<'HEADER'
\clearpage
\section{Interaction DiD --- Protest with \texttt{downup\_ac} (\texttt{\_app\_18})}
HEADER
for i in "${!FE_ARR[@]}"; do
    fe="${FE_ARR[$i]}"
    slot=$((i + 1))
    cat >> "$TEX_PATH" <<EOF
\\subsection*{FE specification \\texttt{fe${fe}} (slot \`evreg${slot}')}
EOF
    emit_figure "app18_protest_did_downup_${slot}.png" "Protest $\\times$ downup\\_ac (fe${fe})"
done
echo "\\FloatBarrier" >> "$TEX_PATH"

cat >> "$TEX_PATH" <<'HEADER'
\clearpage
\section{Interaction DiD --- Politician characteristics with \texttt{downup\_ac} (\texttt{\_app\_19})}
HEADER
for i in "${!FE_ARR[@]}"; do
    fe="${FE_ARR[$i]}"
    slot=$((i + 1))
    cat >> "$TEX_PATH" <<EOF
\\subsection*{FE specification \\texttt{fe${fe}} (slot \`evreg${slot}')}
EOF
    emit_figure "app19_polischar_did_downup_${slot}.png" "Polischar $\\times$ downup\\_ac (fe${fe})"
done
echo "\\FloatBarrier" >> "$TEX_PATH"

cat >> "$TEX_PATH" <<'FOOTER'

\end{document}
FOOTER

echo "Wrote LaTeX: $TEX_PATH"
