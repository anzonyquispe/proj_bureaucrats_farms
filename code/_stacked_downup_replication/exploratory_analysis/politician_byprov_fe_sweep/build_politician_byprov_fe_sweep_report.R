#!/usr/bin/env Rscript

# Build the politician-by-province FE-sweep report.
#
# Each FE specification compares:
#   1. the baseline politician event study (original and detrended); and
#   2. the post x treat x downup_ac_pop DiD interaction produced with the
#      _app_19 interaction_graph.ado methodology.
#
# The old event-time x downup_ac_pop interaction is deliberately excluded.

suppressPackageStartupMessages(library(data.table))

get_script_path <- function() {
  arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(arg)) return(sub("^--file=", "", arg[[1L]]))
  if (interactive() && requireNamespace("rstudioapi", quietly = TRUE)) {
    path <- tryCatch(
      rstudioapi::getSourceEditorContext()$path,
      error = function(...) ""
    )
    if (nzchar(path)) return(path)
  }
  ""
}

find_repo <- function(start) {
  current <- normalizePath(start, winslash = "/", mustWork = FALSE)
  if (file.exists(current)) current <- dirname(current)
  repeat {
    marker <- file.path(current, "code", "_stacked_downup_replication")
    if (dir.exists(marker)) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) break
    current <- parent
  }
  ""
}

script_path <- get_script_path()
repo_root <- find_repo(if (nzchar(script_path)) script_path else getwd())
args <- commandArgs(trailingOnly = TRUE)
if (length(args)) {
  if (length(args) != 2L || args[[1L]] != "--root") {
    stop("Usage: Rscript build_politician_byprov_fe_sweep_report.R [--root REPO]")
  }
  repo_root <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
}
if (!nzchar(repo_root)) stop("Repository root could not be detected.")

table_dir <- file.path(
  repo_root, "tables", "exploratory_analysis", "politician_byprov_fe_sweep"
)
figure_dir <- file.path(
  repo_root, "figures", "exploratory_analysis", "politician_byprov_fe_sweep"
)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

coefficient_path <- file.path(
  table_dir, "politician_byprov_fe_sweep_coefficients.csv"
)
average_path <- file.path(
  table_dir, "politician_byprov_fe_sweep_pre_post_averages.csv"
)
if (!file.exists(coefficient_path) || !file.exists(average_path)) {
  stop("The FE-sweep coefficient and pre/post-average summaries are required.")
}

coefficients <- fread(coefficient_path)
averages <- fread(average_path)
coefficients <- coefficients[model == "baseline"]
averages <- averages[model == "baseline"]

fmt <- function(value) sprintf("%.4f", value)
fmt_ci <- function(lower, upper) sprintf("[%.4f, %.4f]", lower, upper)
latex_path <- function(path) {
  paste0("\\detokenize{", normalizePath(
    path, winslash = "/", mustWork = FALSE
  ), "}")
}

lines <- c(
  "\\documentclass[10pt]{article}",
  "\\usepackage[letterpaper,landscape,margin=0.55in]{geometry}",
  "\\usepackage{graphicx}",
  "\\usepackage{booktabs}",
  "\\usepackage{array}",
  "\\usepackage[hidelinks]{hyperref}",
  "\\usepackage{xcolor}",
  "\\setlength{\\parindent}{0pt}",
  "\\setlength{\\tabcolsep}{4pt}",
  "\\title{Politician Characteristics: Exploratory Fixed-Effect Results}",
  paste0(
    "\\author{Input: \\texttt{politicians\\_characteristics\\_byprov.csv}",
    "\\\\Full unchanged control composition}"
  ),
  "\\date{August 2026}",
  "\\begin{document}",
  "\\maketitle",
  "\\begin{abstract}",
  paste0(
    "This report compares 32 fixed-effect specifications. For each specification, ",
    "the top row presents the baseline politician event study for event years -5 ",
    "through 4, with -1 omitted, before and after pretrend rotation. The lower ",
    "panel presents the DiD interaction of \\texttt{post} $\\times$ \\texttt{treat} ",
    "$\\times$ \\texttt{downup\\_ac\\_pop}, constructed following ",
    "\\texttt{\\_app\\_19\\_polischar\\_fe12\\_did\\_downup\\_inter\\_plot.do}. "
  ),
  paste0(
    "The prior event-time interaction with \\texttt{downup\\_ac\\_pop} is not ",
    "included. Rotated pre-period and post-period averages are computed from the ",
    "rotated coefficients with the corresponding transformed covariance matrix."
  ),
  "\\end{abstract}",
  "\\tableofcontents",
  "\\clearpage"
)

missing_did <- integer()
for (fe_id in 1:32) {
  current_fe <- fe_id
  tag <- sprintf("%02d", fe_id)
  base_stem <- paste0("politician_byprov_fe", tag, "_rural_acpop_all_baseline")
  original_plot <- file.path(figure_dir, paste0(base_stem, "_ori.png"))
  rotated_plot <- file.path(figure_dir, paste0(base_stem, "_rotated.png"))
  did_stem <- paste0(
    "politician_byprov_fe", tag, "_did_interaction_rural_acpop_all_1.png"
  )
  did_plot <- file.path(figure_dir, did_stem)

  if (!file.exists(original_plot) || !file.exists(rotated_plot)) {
    stop("Missing baseline event-study figure(s) for FE ", fe_id)
  }
  did_available <- file.exists(did_plot)
  if (!did_available) missing_did <- c(missing_did, fe_id)

  lines <- c(
    lines,
    paste0("\\section{Fixed-effect specification ", fe_id, "}"),
    "\\begin{center}",
    "\\begin{minipage}[t]{0.48\\textwidth}\\centering",
    "\\textbf{Baseline event study: original}\\par\\smallskip",
    paste0(
      "\\includegraphics[width=\\textwidth]{", latex_path(original_plot), "}"
    ),
    "\\end{minipage}\\hfill",
    "\\begin{minipage}[t]{0.48\\textwidth}\\centering",
    "\\textbf{Baseline event study: pretrend rotated}\\par\\smallskip",
    paste0(
      "\\includegraphics[width=\\textwidth]{", latex_path(rotated_plot), "}"
    ),
    "\\end{minipage}\\par\\medskip",
    "\\textbf{DiD interaction: post $\\times$ treat $\\times$ downup\\_ac\\_pop}\\par\\smallskip"
  )
  if (did_available) {
    lines <- c(
      lines,
      paste0(
        "\\includegraphics[width=0.54\\textwidth]{", latex_path(did_plot), "}"
      )
    )
  } else {
    lines <- c(
      lines,
      "\\fcolorbox{red}{red!5}{\\parbox[c][1.0in][c]{0.66\\textwidth}{\\centering",
      paste0(
        "Corrected DiD interaction output is not yet available for FE ", fe_id,
        ".\\\\Expected file: \\texttt{", gsub("_", "\\\\_", did_stem), "}"
      ),
      "}}"
    )
  }
  lines <- c(lines, "\\end{center}", "\\clearpage")

  coef_fe <- coefficients[fe_id == current_fe]
  avg_fe <- averages[fe_id == current_fe]
  original <- coef_fe[version == "original"]
  rotated <- coef_fe[version == "rotated"]
  setorder(original, time)
  setorder(rotated, time)
  if (nrow(original) != 10L || nrow(rotated) != 10L) {
    stop("Expected ten original and ten rotated event coefficients for FE ", fe_id)
  }

  lines <- c(
    lines,
    paste0("\\subsection*{Baseline event-study estimates: specification ", fe_id, "}"),
    "\\begin{center}",
    "\\scriptsize",
    "\\begin{tabular}{r rr rr}",
    "\\toprule",
    paste0(
      "Event time & Original $\\hat\\beta$ & Original 95\\% CI & ",
      "Rotated $\\hat\\beta$ & Rotated 95\\% CI \\\\"
    ),
    "\\midrule"
  )
  for (row in seq_len(nrow(original))) {
    lines <- c(
      lines,
      paste0(
        original$time[[row]], " & ", fmt(original$beta[[row]]), " & ",
        fmt_ci(original$lower[[row]], original$upper[[row]]), " & ",
        fmt(rotated$beta[[row]]), " & ",
        fmt_ci(rotated$lower[[row]], rotated$upper[[row]]), " \\\\"
      )
    )
  }

  for (period_name in c("pre", "post")) {
    original_avg <- avg_fe[version == "original" & period == period_name]
    rotated_avg <- avg_fe[version == "rotated" & period == period_name]
    label <- if (period_name == "pre") "Pre average" else "Post average"
    lines <- c(
      lines,
      if (period_name == "pre") "\\midrule" else character(),
      paste0(
        label, " & ", fmt(original_avg$estimate), " & ",
        fmt_ci(original_avg$lower, original_avg$upper), " & ",
        fmt(rotated_avg$estimate), " & ",
        fmt_ci(rotated_avg$lower, rotated_avg$upper), " \\\\"
      )
    )
  }
  lines <- c(
    lines,
    "\\bottomrule",
    "\\end{tabular}",
    "\\end{center}",
    "\\medskip",
    paste0(
      "\\textit{The DiD interaction panel is generated from the specification's ",
      "own \\texttt{post} $\\times$ \\texttt{treat} $\\times$ ",
      "\\texttt{downup\\_ac\\_pop} regression using \\texttt{interaction\\_graph.ado}.}"
    ),
    "\\clearpage"
  )
}

lines <- c(
  lines,
  "\\section*{DiD-output availability}",
  if (!length(missing_did)) {
    "All 32 corrected DiD interaction figures were included."
  } else {
    paste0(
      "Corrected DiD interaction figures were unavailable for FE specifications: ",
      paste(missing_did, collapse = ", "), ". The report displays explicit ",
      "placeholders and does not substitute the old event-time interactions."
    )
  },
  "\\end{document}"
)

report_path <- file.path(table_dir, "politician_byprov_fe_sweep_report.tex")
writeLines(lines, report_path, useBytes = TRUE)
message("Generated: ", report_path)
message("Corrected DiD figures present: ", 32L - length(missing_did), "/32")
if (length(missing_did)) {
  message("Missing corrected DiD FE ids: ", paste(missing_did, collapse = ","))
}
