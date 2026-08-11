#!/usr/bin/env Rscript

# Dedicated renderer for politicians_characteristics_byprov.csv FE results.
# RStudio: open this file and click Source.
# CLI: Rscript plot_politician_byprov_fe_sweep.R --root C:/path/to/repository

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})
data.table::setDTthreads(1L)

get_script_path <- function() {
  arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(arg)) return(sub("^--file=", "", arg[[1L]]))
  if (interactive() && requireNamespace("rstudioapi", quietly = TRUE)) {
    path <- tryCatch(rstudioapi::getSourceEditorContext()$path,
                     error = function(...) "")
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
detected_root <- find_repo(if (nzchar(script_path)) script_path else getwd())

# Edit only if automatic detection fails in RStudio.
RSTUDIO_CONFIG <- list(
  root = detected_root,
  output_root = detected_root,
  fe_ids = 1:32
)

parse_args <- function(args) {
  out <- RSTUDIO_CONFIG
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--root" && i < length(args)) {
      out$root <- args[[i + 1L]]
      i <- i + 2L
    } else if (args[[i]] == "--output-root" && i < length(args)) {
      out$output_root <- args[[i + 1L]]
      i <- i + 2L
    } else if (args[[i]] == "--fe-list" && i < length(args)) {
      out$fe_ids <- as.integer(trimws(
        strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]
      ))
      i <- i + 2L
    } else {
      stop("Unknown or incomplete argument: ", args[[i]], call. = FALSE)
    }
  }
  if (!nzchar(out$root) || !nzchar(out$output_root)) {
    stop("Set RSTUDIO_CONFIG paths or provide --root and --output-root.", call. = FALSE)
  }
  if (anyNA(out$fe_ids) || any(!out$fe_ids %in% 1:32)) {
    stop("FE ids must be integers from 1 through 32.", call. = FALSE)
  }
  out$root <- normalizePath(out$root, winslash = "/", mustWork = FALSE)
  out$output_root <- normalizePath(out$output_root, winslash = "/", mustWork = FALSE)
  out
}

cfg <- parse_args(commandArgs(trailingOnly = TRUE))
table_dir <- file.path(
  cfg$root, "tables", "exploratory_analysis", "politician_byprov_fe_sweep"
)
figure_dir <- file.path(
  cfg$output_root, "figures", "exploratory_analysis",
  "politician_byprov_fe_sweep"
)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

mean_test <- function(beta, vcov, indices) {
  weights <- rep(1 / length(indices), length(indices))
  c(
    estimate = sum(weights * beta[indices]),
    se = sqrt(drop(t(weights) %*% vcov[indices, indices, drop = FALSE] %*% weights))
  )
}

extract_event <- function(path, model, rows, columns) {
  estimates <- fread(path)
  selected <- estimates[reg == model]
  if (max(rows) > nrow(selected) || max(columns) > ncol(selected)) {
    stop(basename(path), " / ", model, ": unexpected estsave_csv layout")
  }
  out <- selected[rows, columns, with = FALSE]
  # estsave_csv order is beta, ymean, covariance; plotting expects the reverse.
  out[, c(2L, 1L, seq.int(3L, ncol(out))), with = FALSE]
}

plot_event <- function(event_data, output_stem, detrend = FALSE) {
  event_data <- as.data.table(copy(event_data))
  setnames(event_data, names(event_data)[1:2], c("ymean", "beta"))
  event_data[, beta := as.numeric(beta)]
  vcov <- as.matrix(event_data[, -(1:2)])
  storage.mode(vcov) <- "double"
  if (!identical(dim(vcov), c(9L, 9L))) {
    stop(output_stem, ": expected nine event coefficients and a 9x9 covariance")
  }
  event_data[, `:=`(se = sqrt(diag(vcov)), time = c(-5:-2, 0:4))]
  full <- rbind(
    event_data[, .(time, beta, se)],
    data.table(time = -1L, beta = 0, se = 0)
  )
  setorder(full, time)

  pre <- mean_test(event_data$beta, vcov, 1:4)
  post <- mean_test(event_data$beta, vcov, 5:9)
  dep_mean <- mean(as.numeric(event_data$ymean), na.rm = TRUE)
  suffix <- "_ori"
  y_label <- "Effect on Number of Fires (in 1,000 units)"
  if (detrend) {
    full[, shifted_time := time + 1]
    pretrend <- lm(beta ~ shifted_time - 1, data = full[shifted_time <= 0])
    full[, beta := beta - predict(pretrend, newdata = full)]
    suffix <- "_rotated"
    y_label <- "Detrended Effect on Fires (in 1,000 units)"
  }
  full[, `:=`(lower = beta - 1.96 * se, upper = beta + 1.96 * se)]
  y_range <- diff(range(c(full$lower, full$upper), na.rm = TRUE))
  if (!is.finite(y_range) || y_range == 0) y_range <- 1
  annotation <- data.table(
    time = min(full$time),
    value = max(full$upper, na.rm = TRUE) - (0:2) * 0.08 * y_range,
    label = c(
      sprintf("Mean DV = %.3f", dep_mean),
      sprintf("Pre Avg = %.3f (%.3f)", pre[["estimate"]], pre[["se"]]),
      sprintf("Post Avg = %.3f (%.3f)", post[["estimate"]], post[["se"]])
    )
  )

  plot <- ggplot(full, aes(time, beta)) +
    geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#279FF5", alpha = 0.2) +
    geom_line(colour = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
    geom_vline(xintercept = -1, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    scale_x_continuous(breaks = -5:4) +
    geom_text(
      data = annotation, aes(x = time, y = value, label = label),
      inherit.aes = FALSE, hjust = 0, vjust = 1, size = 3.6
    ) +
    labs(x = "Years from Election", y = y_label) +
    theme_classic(base_size = 12) +
    theme(
      panel.grid.major = element_line(colour = "grey85", linetype = "dashed"),
      panel.grid.minor = element_blank()
    )
  output <- file.path(figure_dir, paste0(output_stem, suffix, ".png"))
  ggsave(output, plot, width = 8, height = 4, dpi = 300)
  message("Generated: ", output)
}

expected <- character()
completed <- integer()
for (fe_id in cfg$fe_ids) {
  stem <- paste0("politician_byprov_fe", sprintf("%02d", fe_id), "_rural_acpop_all")
  csv_path <- file.path(table_dir, paste0(stem, ".csv"))
  expected <- c(expected, csv_path)
  if (!file.exists(csv_path)) next

  # Same tested estsave_csv locations used by the established politician plot.
  baseline <- extract_event(csv_path, "evreg1", 13:21, c(3, 4, 17:25))
  interaction <- extract_event(csv_path, "evreg2", 33:41, c(3, 4, 37:45))
  plot_event(baseline, paste0(stem, "_baseline"), FALSE)
  plot_event(baseline, paste0(stem, "_baseline"), TRUE)
  plot_event(interaction, paste0(stem, "_interaction"), FALSE)
  plot_event(interaction, paste0(stem, "_interaction"), TRUE)
  completed <- c(completed, fe_id)
}

missing <- expected[!file.exists(expected)]
if (length(missing)) {
  warning(
    "Missing ", length(missing), " result CSV file(s); available results were plotted:\n",
    paste(basename(missing), collapse = "\n"), call. = FALSE
  )
}

# Politician-only, two-column LaTeX atlas. The protest columns will be added in
# the later protest stage without changing these estimates.
atlas_path <- file.path(table_dir, "politician_byprov_fe_sweep_all.tex")
atlas <- c(
  "% Auto-generated by plot_politician_byprov_fe_sweep.R.",
  "% Left: baseline. Right: interaction with downup_ac_pop."
)
for (fe_id in completed) {
  fe_tag <- sprintf("%02d", fe_id)
  stem <- paste0("politician_byprov_fe", fe_tag, "_rural_acpop_all")
  rel_dir <- "figures/exploratory_analysis/politician_byprov_fe_sweep"
  atlas <- c(
    atlas,
    "\\clearpage",
    "\\begin{figure}[p]",
    "\\centering",
    paste0(
      "\\includegraphics[width=0.49\\textwidth]{", rel_dir, "/",
      stem, "_baseline_ori.png}%"
    ),
    paste0(
      "\\includegraphics[width=0.49\\textwidth]{", rel_dir, "/",
      stem, "_interaction_ori.png}"
    ),
    paste0(
      "\\caption{Politician event studies, fixed-effect specification ",
      fe_id, ".}"
    ),
    paste0("\\label{fig:politician-byprov-fe", fe_tag, "}"),
    "\\end{figure}"
  )
}
writeLines(atlas, atlas_path, useBytes = TRUE)
message("Generated: ", atlas_path)
message("Politician by-province FE plotting completed.")

