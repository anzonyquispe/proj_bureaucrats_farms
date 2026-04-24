#!/bin/bash
# build_report_tex.sh
# Emit a LaTeX file arranging, for each FE spec, a 4-col x 3-row panel:
#
#   cols 1-2 = rural pixels (is_rural_area)
#   cols 3-4 = rural pixels (is_rural_farzad)
#
#   row 1 = politician/fire event study (_app_16): ori + rotated per variant
#   row 2 = protest event study         (_app_17): ori + rotated per variant
#   row 3 = interactions with downup_ac:
#           cols 1-2 = area   (polischar _app_19, protest _app_18)
#           cols 3-4 = farzad (polischar _app_19, protest _app_18)
#
# Each section header shows the FE label AND a human-readable description of
# which fixed effects are included. A legend section at the front maps FE
# number -> components.
#
# Required env vars:
#   PLOT_DIR : absolute path to plotting/ folder
#   FIG_DIR  : absolute path to figures directory
#   TEX_PATH : absolute path of the .tex file to write
#   FE_ALL   : space-separated FE numlist, e.g. "1 2 ... 32"

set -u
: "${PLOT_DIR:?}"; : "${FIG_DIR:?}"; : "${TEX_PATH:?}"; : "${FE_ALL:?}"

read -r -a FE_ARR <<< "$FE_ALL"

#-------------------------------------------------------------------------------
# FE descriptions
#
# Every spec starts from the base  G  = grid x cohort. Additional components
# (from _app_16_polischar_evst_all.do):
#   M = month-year x cohort                        (monthyearco)
#   T = province x cohort linear month-year trend  (province_cohort#c.monthyear)
#   Y = government-year                            (yeargov)
#   E = province x election-year                   (province_cohort#election_year)
#   P = province x election-year x government-year (province_cohort#election_year#yeargov)
#-------------------------------------------------------------------------------

BASE='grid$\times$cohort'
M='mo-yr$\times$cohort'
T='prov$\times$cohort trend'
Y='govt-year'
E='prov$\times$elec-yr'
P='prov$\times$elec-yr$\times$govt-yr'

declare -a FE_DESC
FE_DESC[1]="$BASE"
FE_DESC[2]="$BASE + $M"
FE_DESC[3]="$BASE + $T"
FE_DESC[4]="$BASE + $Y"
FE_DESC[5]="$BASE + $E"
FE_DESC[6]="$BASE + $P"
FE_DESC[7]="$BASE + $M + $T"
FE_DESC[8]="$BASE + $M + $Y"
FE_DESC[9]="$BASE + $M + $E"
FE_DESC[10]="$BASE + $M + $P"
FE_DESC[11]="$BASE + $T + $Y"
FE_DESC[12]="$BASE + $T + $E"
FE_DESC[13]="$BASE + $T + $P"
FE_DESC[14]="$BASE + $Y + $E"
FE_DESC[15]="$BASE + $Y + $P"
FE_DESC[16]="$BASE + $E + $P"
FE_DESC[17]="$BASE + $M + $T + $Y"
FE_DESC[18]="$BASE + $M + $T + $E"
FE_DESC[19]="$BASE + $M + $T + $P"
FE_DESC[20]="$BASE + $M + $Y + $E"
FE_DESC[21]="$BASE + $M + $Y + $P"
FE_DESC[22]="$BASE + $M + $E + $P"
FE_DESC[23]="$BASE + $T + $Y + $E"
FE_DESC[24]="$BASE + $T + $Y + $P"
FE_DESC[25]="$BASE + $T + $E + $P"
FE_DESC[26]="$BASE + $Y + $E + $P"
FE_DESC[27]="$BASE + $M + $T + $Y + $E"
FE_DESC[28]="$BASE + $M + $T + $Y + $P"
FE_DESC[29]="$BASE + $M + $T + $E + $P"
FE_DESC[30]="$BASE + $M + $Y + $E + $P"
FE_DESC[31]="$BASE + $T + $Y + $E + $P"
FE_DESC[32]="$BASE + $M + $T + $Y + $E + $P"

# Short extras-only label for the at-a-glance index table.
declare -a FE_EXTRAS
FE_EXTRAS[1]="---"
FE_EXTRAS[2]="M"
FE_EXTRAS[3]="T"
FE_EXTRAS[4]="Y"
FE_EXTRAS[5]="E"
FE_EXTRAS[6]="P"
FE_EXTRAS[7]="M, T"
FE_EXTRAS[8]="M, Y"
FE_EXTRAS[9]="M, E"
FE_EXTRAS[10]="M, P"
FE_EXTRAS[11]="T, Y"
FE_EXTRAS[12]="T, E"
FE_EXTRAS[13]="T, P"
FE_EXTRAS[14]="Y, E"
FE_EXTRAS[15]="Y, P"
FE_EXTRAS[16]="E, P"
FE_EXTRAS[17]="M, T, Y"
FE_EXTRAS[18]="M, T, E"
FE_EXTRAS[19]="M, T, P"
FE_EXTRAS[20]="M, Y, E"
FE_EXTRAS[21]="M, Y, P"
FE_EXTRAS[22]="M, E, P"
FE_EXTRAS[23]="T, Y, E"
FE_EXTRAS[24]="T, Y, P"
FE_EXTRAS[25]="T, E, P"
FE_EXTRAS[26]="Y, E, P"
FE_EXTRAS[27]="M, T, Y, E"
FE_EXTRAS[28]="M, T, Y, P"
FE_EXTRAS[29]="M, T, E, P"
FE_EXTRAS[30]="M, Y, E, P"
FE_EXTRAS[31]="T, Y, E, P"
FE_EXTRAS[32]="M, T, Y, E, P"

#-------------------------------------------------------------------------------
# helpers
#-------------------------------------------------------------------------------

fig_rel() {
    python3 - <<PY
import os
print(os.path.relpath("$FIG_DIR/$1", start=os.path.dirname("$TEX_PATH")))
PY
}

emit_cell() {
    local path="$1"
    if [[ -f "$FIG_DIR/$path" ]]; then
        local rel; rel="$(fig_rel "$path")"
        echo "\\includegraphics[width=\\linewidth,height=4.2cm,keepaspectratio]{${rel}}"
    else
        echo "\\fbox{\\parbox[c][4.2cm][c]{\\linewidth}{\\centering\\texttt{missing}\\\\\\tiny{$path}}}"
    fi
}

mkdir -p "$(dirname "$TEX_PATH")"

#-------------------------------------------------------------------------------
# Header + legend
#-------------------------------------------------------------------------------

cat > "$TEX_PATH" <<'HEADER'
\documentclass[10pt,landscape]{article}
\usepackage[margin=0.5in]{geometry}
\usepackage{graphicx}
\usepackage{float}
\usepackage{caption}
\usepackage{subcaption}
\usepackage{hyperref}
\usepackage{placeins}
\usepackage{array}
\usepackage{booktabs}
\usepackage{longtable}

\captionsetup[figure]{skip=3pt}
\setlength{\tabcolsep}{2pt}
\renewcommand{\arraystretch}{1.1}

\title{Rural Analysis --- Full Report\\\large Area vs.\ Farzad Classification, All 32 FE Specs}
\author{proj\_bureaucrats\_farms}
\date{\today}

\begin{document}
\maketitle

\noindent
For each fixed-effect specification, this report arranges a 4-column by
3-row grid.

\begin{itemize}
\itemsep0em
\item Columns~1--2: rural pixels classified by area (\texttt{is\_rural\_area}).
\item Columns~3--4: rural pixels classified by the Farzad methodology
      (\texttt{is\_rural\_farzad}) --- any urban pixel touching the grid.
\item Row~1: politician/fire event study (\texttt{\_app\_16}), original and
      linear-detrended (``rotated'') panels per variant.
\item Row~2: protest event study (\texttt{\_app\_17}), same two forms per variant.
\item Row~3: triple-interaction DiD with \texttt{downup\_ac} ---
      polischar (\texttt{\_app\_19}) and protest (\texttt{\_app\_18})
      side-by-side per variant.
\end{itemize}

\clearpage

\section*{Fixed-effects legend}

\noindent Every specification includes the base \textbf{grid $\times$ cohort}
fixed effect (\texttt{unique\_small\_grid\_id\_cohort}). The table below lists
the additional components combined in each FE spec.

\vspace{0.5em}
\noindent
\begin{tabular}{@{}cl@{}}
\toprule
\textbf{Code} & \textbf{Component} \\
\midrule
M & month-year $\times$ cohort \quad (\texttt{monthyearco}) \\
T & province $\times$ cohort linear month-year trend \quad (\texttt{province\_cohort\#c.monthyear}) \\
Y & government-year \quad (\texttt{yeargov}) \\
E & province $\times$ election-year \quad (\texttt{province\_cohort\#election\_year}) \\
P & province $\times$ election-year $\times$ government-year \quad (\texttt{province\_cohort\#election\_year\#yeargov}) \\
\bottomrule
\end{tabular}

\vspace{1.2em}
\noindent
\begin{longtable}{@{}cl@{\hspace{3em}}cl@{}}
\toprule
\textbf{FE} & \textbf{Extras beyond grid $\times$ cohort} &
\textbf{FE} & \textbf{Extras beyond grid $\times$ cohort} \\
\midrule
\endfirsthead
\toprule
\textbf{FE} & \textbf{Extras beyond grid $\times$ cohort} &
\textbf{FE} & \textbf{Extras beyond grid $\times$ cohort} \\
\midrule
\endhead
HEADER

# Pair rows: fe1 & fe17, fe2 & fe18, ..., fe16 & fe32
for i in $(seq 1 16); do
    j=$((i + 16))
    cat >> "$TEX_PATH" <<EOF
\\texttt{fe${i}} & ${FE_EXTRAS[$i]} & \\texttt{fe${j}} & ${FE_EXTRAS[$j]} \\\\
EOF
done

cat >> "$TEX_PATH" <<'LEGENDEND'
\bottomrule
\end{longtable}

\clearpage

\tableofcontents
\clearpage

LEGENDEND

#-------------------------------------------------------------------------------
# One section per FE spec
#-------------------------------------------------------------------------------

for fe in "${FE_ARR[@]}"; do
    desc="${FE_DESC[$fe]}"
    cat >> "$TEX_PATH" <<EOF
\\section*{Fixed-effects specification \\texttt{fe${fe}}}
\\addcontentsline{toc}{section}{fe${fe} --- ${desc}}
\\noindent\\textit{${desc}}
\\vspace{0.5em}

\\noindent
\\begin{tabular}{@{}m{0.245\\linewidth}m{0.245\\linewidth}m{0.245\\linewidth}m{0.245\\linewidth}@{}}
\\centering\\arraybackslash\\textbf{Area --- original} &
\\centering\\arraybackslash\\textbf{Area --- rotated} &
\\centering\\arraybackslash\\textbf{Farzad --- original} &
\\centering\\arraybackslash\\textbf{Farzad --- rotated} \\\\[2pt]

\\centering\\arraybackslash $(emit_cell "app16_polischar_evst_fe${fe}_area_ori.png") &
\\centering\\arraybackslash $(emit_cell "app16_polischar_evst_fe${fe}_area_rotated.png") &
\\centering\\arraybackslash $(emit_cell "app16_polischar_evst_fe${fe}_farzad_ori.png") &
\\centering\\arraybackslash $(emit_cell "app16_polischar_evst_fe${fe}_farzad_rotated.png") \\\\
\\multicolumn{4}{@{}c@{}}{\\footnotesize\\emph{Row 1 --- Politician event study (\\texttt{\\_app\\_16})}} \\\\[4pt]

\\centering\\arraybackslash $(emit_cell "app17_protest_evst_fe${fe}_area_ori.png") &
\\centering\\arraybackslash $(emit_cell "app17_protest_evst_fe${fe}_area_rotated.png") &
\\centering\\arraybackslash $(emit_cell "app17_protest_evst_fe${fe}_farzad_ori.png") &
\\centering\\arraybackslash $(emit_cell "app17_protest_evst_fe${fe}_farzad_rotated.png") \\\\
\\multicolumn{4}{@{}c@{}}{\\footnotesize\\emph{Row 2 --- Protest event study (\\texttt{\\_app\\_17})}} \\\\[4pt]

\\centering\\arraybackslash $(emit_cell "app19_polischar_did_downup_fe${fe}_area.png") &
\\centering\\arraybackslash $(emit_cell "app18_protest_did_downup_fe${fe}_area.png") &
\\centering\\arraybackslash $(emit_cell "app19_polischar_did_downup_fe${fe}_farzad.png") &
\\centering\\arraybackslash $(emit_cell "app18_protest_did_downup_fe${fe}_farzad.png") \\\\
\\multicolumn{4}{@{}c@{}}{\\footnotesize\\emph{Row 3 --- Interactions with \\texttt{downup\\_ac}: polischar (\\texttt{\\_app\\_19}) and protest (\\texttt{\\_app\\_18})}} \\\\
\\end{tabular}
\\clearpage
EOF
done

cat >> "$TEX_PATH" <<'FOOTER'

\end{document}
FOOTER

echo "Wrote LaTeX: $TEX_PATH"
