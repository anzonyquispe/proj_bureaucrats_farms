#!/usr/bin/env Rscript

# Build the LaTeX/PDF-ready report for the three Q-weighted specifications.
suppressPackageStartupMessages(library(data.table))

repo <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
tables <- file.path(
  repo, "tables", "exploratory_analysis", "politician_byprov_stack_weights"
)
figures <- file.path(
  repo, "figures", "exploratory_analysis", "politician_byprov_stack_weights"
)
output <- file.path(repo, "output", "pdf")
dir.create(output, recursive = TRUE, showWarnings = FALSE)

metadata <- fread(file.path(tables, "analysis_metadata.csv"))[1]
selection <- fread(file.path(tables, "cohort_coverage.csv"))
table_tex <- file.path(tables, "weighted_event_study_table.tex")
specs <- c(original = "Original stacked FE", fe01 = "FE 01", fe05 = "FE 05")
plots <- file.path(figures, paste0("politician_qweight_", names(specs), "_ori.png"))
interaction_plots <- file.path(
  figures, paste0("politician_qweight_", names(specs), "_interaction.png")
)
stopifnot(
  file.exists(table_tex), all(file.exists(plots)), all(file.exists(interaction_plots))
)

latex_path <- function(path) paste0(
  "\\detokenize{", normalizePath(path, winslash = "/", mustWork = TRUE), "}"
)

cohort_rows <- selection[, {
  election <- sprintf("%d-%02d", cohort_year, cohort_month)
  window <- sprintf("%d to %d", min_event, max_event)
  decision <- "Include"
  paste0(cohort_id, " & ", province, " & ", election, " & ", window,
         " & ", decision, " \\\\")
}]

lines <- c(
  "\\documentclass[10pt]{article}",
  "\\usepackage[letterpaper,landscape,margin=0.55in]{geometry}",
  "\\usepackage{graphicx}",
  "\\usepackage{booktabs}",
  "\\usepackage{amsmath}",
  "\\usepackage{float}",
  "\\usepackage[hidelinks]{hyperref}",
  "\\setlength{\\parindent}{0pt}",
  "\\title{Q-Weighted Politician Event Studies}",
  "\\author{Exploratory fixed-effect comparison}",
  "\\date{August 18, 2026}",
  "\\begin{document}",
  "\\maketitle",
  "\\textbf{Connection to the paper.} This exploratory analysis applies the ",
  "corrective Q-weighted stacked difference-in-differences estimator from ",
  "\\href{https://doi.org/10.3386/w32054}{Wing, Freedman, and Hollingsworth ",
  "(2024), \\textit{Stacked Difference-in-Differences}}. We replicate their ",
  "method and their original fixed-effect specification, not their numerical ",
  "Medicaid results: the estimates below are for fires in this project. The ",
  "paper's preferred fixed-composition target is a trimmed aggregate ATT.",
  "",
  "\\textbf{What cohort ID means.} A cohort ID labels one stacked ",
  "sub-experiment (a province-election pair); it does not label a control type. ",
  "Every included cohort contains both treated observations ($treat=1$) and ",
  "controls ($treat=0$). All $treat=0$ observations are included because they ",
  "remain untreated throughout that stack's analysis window; no distinction ",
  "among control types is used.",
  "",
  "\\textbf{All cohorts are included.} No cohort is discarded for lacking ",
  "some leads or lags. Each sub-experiment contributes only at the event years ",
  "available in the data. Thus IDs 3--6 contribute from -5 through 4; IDs 1--2 ",
  "enter later; and IDs 7--8 leave after event year 2.",
  "\\begin{center}",
  "\\small",
  "\\begin{tabular}{rllll}",
  "\\toprule",
  "ID & Province & Election & Available event years & Used? \\\\",
  "\\midrule",
  cohort_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{center}",
  "\\textbf{Corrective weights.} For cohort $s$ and event year $e$, treated ",
  "observations receive weight one and controls receive",
  "\\[Q_{se}=\\frac{n^T_{se}/N^T_e}{n^C_{se}/N^C_e}.\\]",
  "At each event year, this makes the weighted cohort shares among controls ",
  "match the shares among treated observations for the cohorts available at ",
  "that event year, which is the paper's corrective-weight principle.",
  "",
  "\\textbf{Estimand caveat.} Because cohort availability changes over event ",
  "time, this requested all-cohort specification is not the paper's ",
  "fixed-composition trimmed aggregate ATT over -5 through 4. Event year -5 ",
  "uses IDs 3--8; -4 uses IDs 2--8; -3 through 2 use IDs 1--8; and 3--4 use ",
  "IDs 1--6. Consequently, differences across event years can reflect both ",
  "dynamic effects and changes in the contributing cohorts.",
  "\\clearpage",
  "\\section*{Event-study estimates}",
  "Event years run from -5 through 4, with -1 omitted. ",
  paste0(
    "The sample contains ", format(metadata$observations, big.mark = ","),
    " observations from cohort IDs ", metadata$cohorts, ". All models include ",
    "wind direction and average wind speed, use ",
    "Q-weights, and cluster standard errors by AC $\\times$ cohort."
  ),
  paste0(
    " Control weights range from ",
    sprintf("%.3f", metadata$min_control_weight), " to ",
    sprintf("%.3f", metadata$max_control_weight), "."
  ),
  "",
  "\\textbf{Specifications.} Original stacked FE absorbs treatment-group and ",
  "relative-year effects. FE 01 absorbs grid $\\times$ cohort effects. FE 05 ",
  "absorbs grid $\\times$ cohort and province $\\times$ cohort $\\times$ ",
  "election-year effects.",
  "",
  "\\begin{figure}[H]",
  "\\centering"
)

for (i in seq_along(specs)) {
  lines <- c(
    lines,
    "\\begin{minipage}[t]{0.325\\textwidth}",
    "\\centering",
    paste0("\\textbf{", specs[[i]], "}\\par\\smallskip"),
    paste0("\\includegraphics[width=\\linewidth]{", latex_path(plots[[i]]), "}"),
    "\\end{minipage}",
    if (i < length(specs)) "\\hfill" else character()
  )
}

lines <- c(
  lines,
  "\\caption{Q-weighted event-study estimates and 95\\% confidence intervals.}",
  "\\end{figure}",
  "\\clearpage",
  "\\section*{Q-weighted DiD interactions}",
  "The two post-treatment estimates are intentionally offset horizontally. ",
  "Their coefficient values and confidence intervals are unchanged; the added ",
  "space only makes overlapping 90\\% and 95\\% intervals visible.",
  "\\begin{figure}[H]",
  "\\centering"
)

for (i in seq_along(specs)) {
  lines <- c(
    lines,
    if (i == 3L) "\\par\\medskip" else character(),
    "\\begin{minipage}[t]{0.44\\textwidth}",
    "\\centering",
    paste0("\\textbf{", specs[[i]], "}\\par\\smallskip"),
    paste0(
      "\\includegraphics[width=\\linewidth]{",
      latex_path(interaction_plots[[i]]), "}"
    ),
    "\\end{minipage}",
    if (i == 1L) "\\hfill" else character()
  )
}

lines <- c(
  lines,
  "\\caption{Q-weighted pre/post interactions with separated post positions.}",
  "\\end{figure}",
  "\\clearpage",
  "\\section*{Regression estimates}",
  paste0("\\input{", latex_path(table_tex), "}"),
  "\\vfill",
  "\\footnotesize\\textit{Notes:} The omitted event year is -1. The dependent ",
  "variable is the project-standard fire count multiplied by 1,000. The same ",
  "complete-case, all-cohort sample and Q-weights are used in all three ",
  "columns. Cohort composition varies with event-time coverage. Method: ",
  "\\href{https://doi.org/10.3386/w32054}{Wing, ",
  "Freedman, and Hollingsworth (2024)}. Implementation reference: ",
  "\\href{https://github.com/hollina/stacked-did-weights}{authors' example ",
  "code}.",
  "\\end{document}"
)

writeLines(lines, file.path(output, "politician_qweighted_event_study_report.tex"))
cat("Generated LaTeX report in", output, "\n")
