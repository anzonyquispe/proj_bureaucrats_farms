#!/usr/bin/env Rscript

# Build one LaTeX report per control definition. Each FE page contains the
# original event study, its pretrend-rotated version, and exactly one non-
# rotated _app_19-style DiD interaction plot.

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
    if (dir.exists(file.path(current, "code", "_stacked_downup_replication"))) {
      return(current)
    }
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
    stop("Usage: Rscript build_politician_original_controls_reports.R [--root REPO]")
  }
  repo_root <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
}
if (!nzchar(repo_root)) stop("Repository root could not be detected.")

relative_dir <- file.path(
  "exploratory_analysis", "politician_original_controls_fe_sweep"
)
table_dir <- file.path(repo_root, "tables", relative_dir)
figure_dir <- file.path(repo_root, "figures", relative_dir)
report_dir <- file.path(repo_root, "code", "_report")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
coefficient_path <- file.path(
  table_dir, "politician_original_controls_coefficients.csv"
)
average_path <- file.path(
  table_dir, "politician_original_controls_pre_post_averages.csv"
)
if (!file.exists(coefficient_path) || !file.exists(average_path)) {
  stop("Run plot_politician_original_controls_fe_sweep.R first.")
}

coefficients <- fread(coefficient_path)
averages <- fread(average_path)
fmt <- function(value) sprintf("%.4f", value)
fmt_ci <- function(lower, upper) sprintf("[%.4f, %.4f]", lower, upper)
latex_path <- function(path) {
  paste0(
    "\\detokenize{",
    normalizePath(path, winslash = "/", mustWork = TRUE),
    "}"
  )
}

control_labels <- c(
  never = "Never-treated controls",
  both = "Never-treated and not-yet-treated controls",
  notyet = "Legacy not-yet/partial-zero-spell controls"
)

for (control_sample in names(control_labels)) {
  current_control <- control_sample
  report_stem <- paste0(
    "politician_original_controls_", control_sample, "_report"
  )
  lines <- c(
    "\\documentclass[10pt]{article}",
    "\\usepackage[letterpaper,landscape,margin=0.55in]{geometry}",
    "\\usepackage{graphicx}",
    "\\usepackage{booktabs}",
    "\\usepackage{array}",
    "\\usepackage[hidelinks]{hyperref}",
    "\\setlength{\\parindent}{0pt}",
    "\\setlength{\\tabcolsep}{4pt}",
    "\\title{Politician Characteristics: Exploratory Fixed-Effect Results}",
    paste0(
      "\\author{Original \\texttt{politicians\\_characteristics.csv}",
      "\\\\", control_labels[[control_sample]], "}"
    ),
    "\\date{August 2026}",
    "\\begin{document}",
    "\\maketitle",
    "\\begin{abstract}",
    paste0(
      "This report compares 32 fixed-effect specifications using ",
      control_labels[[control_sample]], ". Each specification presents the ",
      "baseline politician event study for event years -5 through 4, with -1 ",
      "omitted, before and after pretrend rotation. It also presents one ",
      "non-rotated DiD interaction plot for \\texttt{post} $\\times$ ",
      "\\texttt{treat} $\\times$ \\texttt{downup\\_ac\\_pop}, following ",
      "\\texttt{\\_app\\_19\\_polischar\\_fe12\\_did\\_downup\\_inter\\_plot.do}."
    ),
    "\\end{abstract}",
    "\\tableofcontents",
    "\\clearpage"
  )

  for (fe_id in 1:32) {
    current_fe <- fe_id
    tag <- sprintf("%02d", fe_id)
    stem <- paste0(
      "politician_original_fe", tag,
      "_controls_", control_sample
    )
    original_plot <- file.path(figure_dir, paste0(stem, "_event_ori.png"))
    rotated_plot <- file.path(
      figure_dir, paste0(stem, "_event_rotated.png")
    )
    did_plot <- file.path(
      figure_dir,
      paste0(stem, "_did_interaction_rural_acpop_all_1.png")
    )
    required_plots <- c(original_plot, rotated_plot, did_plot)
    missing_plots <- required_plots[!file.exists(required_plots)]
    if (length(missing_plots)) {
      stop(
        "Missing report figure(s) for controls=", control_sample,
        ", FE=", fe_id, ":\n", paste(missing_plots, collapse = "\n")
      )
    }

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
      "\\textbf{DiD interaction: post $\\times$ treat $\\times$ downup\\_ac\\_pop}\\par\\smallskip",
      paste0(
        "\\includegraphics[width=0.54\\textwidth]{", latex_path(did_plot), "}"
      ),
      "\\end{center}",
      "\\clearpage"
    )

    coef_fe <- coefficients[
      control_sample == current_control & fe_id == current_fe
    ]
    avg_fe <- averages[
      control_sample == current_control & fe_id == current_fe
    ]
    original <- coef_fe[version == "original"]
    rotated <- coef_fe[version == "rotated"]
    setorder(original, time)
    setorder(rotated, time)
    if (nrow(original) != 10L || nrow(rotated) != 10L) {
      stop("Expected ten event coefficients for FE ", fe_id)
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
      original_avg <- avg_fe[
        version == "original" & period == period_name
      ]
      rotated_avg <- avg_fe[
        version == "rotated" & period == period_name
      ]
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
        "\\textit{The interaction panel comes from this FE specification's ",
        "own \\texttt{post} $\\times$ \\texttt{treat} $\\times$ ",
        "\\texttt{downup\\_ac\\_pop} regression and is not rotated.}"
      ),
      "\\clearpage"
    )
  }

  lines <- c(lines, "\\end{document}")
  report_path <- file.path(report_dir, paste0(report_stem, ".tex"))
  writeLines(lines, report_path, useBytes = TRUE)
  message("Generated: ", report_path)
}
