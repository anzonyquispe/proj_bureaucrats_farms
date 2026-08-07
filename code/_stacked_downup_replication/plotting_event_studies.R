#!/usr/bin/env Rscript

# Single entry point for every event-study and HonestDiD plot produced by the
# stacked/down-up replication package. The politician and protest families are
# rendered for never-treated, pooled never/not-yet-treated, and not-yet-treated
# control samples. Baseline (never-treated) filenames remain unchanged.
#
# RStudio use:
#   1. Open this file in RStudio.
#   2. Edit RSTUDIO_CONFIG below only if the repository is not detected.
#   3. Click Source. Results are read from <repo>/tables and written to
#      <repo>/figures.

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(HonestDiD)
})

# Match the one-CPU scheduler allocation in sbatch/run_r.sbatch.
data.table::setDTthreads(threads = 1L)

get_script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg)) {
    return(sub("^--file=", "", file_arg[[1L]]))
  }
  if (interactive() && requireNamespace("rstudioapi", quietly = TRUE)) {
    path <- tryCatch(
      rstudioapi::getSourceEditorContext()$path,
      error = function(...) ""
    )
    if (nzchar(path)) return(path)
  }
  ""
}

find_repo_root <- function(start) {
  current <- normalizePath(start, winslash = "/", mustWork = FALSE)
  if (file.exists(current)) current <- dirname(current)
  repeat {
    marker <- file.path(
      current, "code", "_stacked_downup_replication",
      "plotting_event_studies.R"
    )
    if (file.exists(marker)) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) break
    current <- parent
  }
  ""
}

script_path <- get_script_path()
repo_start <- if (nzchar(script_path)) script_path else getwd()
detected_repo_root <- find_repo_root(repo_start)

# --------------------------- RSTUDIO SETTINGS ---------------------------
# Usually no edits are needed. Set either path explicitly only if automatic
# repository detection fails. `sample` is the optional filename suffix.
RSTUDIO_CONFIG <- list(
  root = detected_repo_root,
  output_root = detected_repo_root,
  sample = "",
  # Choose any of: "main", "politician", "protest".
  families = c("main", "politician", "protest"),
  # For the main family, optionally list registry IDs; empty means all cases.
  cases = character(),
  # Set FALSE for fast original/detrended plots while developing.
  honest = TRUE
)
# -----------------------------------------------------------------------

parse_args <- function(args) {
  out <- list(
    root = Sys.getenv("REPLICATION_ROOT", unset = RSTUDIO_CONFIG$root),
    output_root = Sys.getenv(
      "REPLICATION_OUTPUT_ROOT", unset = RSTUDIO_CONFIG$output_root
    ),
    sample = Sys.getenv("REPLICATION_SAMPLE", unset = RSTUDIO_CONFIG$sample),
    families = Sys.getenv(
      "REPLICATION_PLOT_FAMILIES",
      unset = paste(RSTUDIO_CONFIG$families, collapse = ",")
    ),
    cases = Sys.getenv(
      "REPLICATION_PLOT_CASES",
      unset = paste(RSTUDIO_CONFIG$cases, collapse = ",")
    ),
    honest = RSTUDIO_CONFIG$honest
  )
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--root" && i < length(args)) {
      out$root <- args[[i + 1L]]
      i <- i + 2L
    } else if (args[[i]] == "--sample") {
      # Treat a trailing --sample, or --sample followed by another option, as
      # an explicitly empty suffix. This is convenient in PowerShell.
      has_value <- i < length(args) && !startsWith(args[[i + 1L]], "--")
      out$sample <- if (has_value) args[[i + 1L]] else ""
      if (identical(out$sample, "none")) out$sample <- ""
      i <- i + if (has_value) 2L else 1L
    } else if (args[[i]] == "--output-root" && i < length(args)) {
      out$output_root <- args[[i + 1L]]
      i <- i + 2L
    } else if (args[[i]] == "--families" && i < length(args)) {
      out$families <- args[[i + 1L]]
      i <- i + 2L
    } else if (args[[i]] == "--cases" && i < length(args)) {
      out$cases <- args[[i + 1L]]
      i <- i + 2L
    } else if (args[[i]] == "--skip-honest") {
      out$honest <- FALSE
      i <- i + 1L
    } else {
      stop("Unknown or incomplete argument: ", args[[i]])
    }
  }
  if (!nzchar(out$root)) {
    stop(
      "Repository root not detected. Set RSTUDIO_CONFIG$root or supply --root.",
      call. = FALSE
    )
  }
  if (!nzchar(out$output_root)) {
    stop(
      paste0(
        "Output root not detected. Set RSTUDIO_CONFIG$output_root or supply ",
        "--output-root."
      ),
      call. = FALSE
    )
  }
  out$root <- normalizePath(out$root, winslash = "/", mustWork = FALSE)
  out$output_root <- normalizePath(
    out$output_root, winslash = "/", mustWork = FALSE
  )
  out$families <- trimws(strsplit(out$families, ",", fixed = TRUE)[[1L]])
  allowed_families <- c("main", "politician", "protest")
  invalid_families <- setdiff(out$families, allowed_families)
  if (length(invalid_families)) {
    stop(
      "Unknown plot family: ", paste(invalid_families, collapse = ", "),
      ". Use main, politician, and/or protest.",
      call. = FALSE
    )
  }
  out$cases <- if (nzchar(out$cases)) {
    trimws(strsplit(out$cases, ",", fixed = TRUE)[[1L]])
  } else {
    character()
  }
  out
}

mean_test <- function(beta, vcov, indices) {
  weights <- rep(1 / length(indices), length(indices))
  selected <- beta[indices]
  selected_vcov <- vcov[indices, indices, drop = FALSE]
  c(
    estimate = sum(weights * selected),
    se = sqrt(drop(t(weights) %*% selected_vcov %*% weights))
  )
}

save_honest <- function(beta, vcov, file_base, suffix, pre, post, m_max = 1) {
  original <- HonestDiD::constructOriginalCS(
    betahat = beta,
    sigma = vcov,
    numPrePeriods = pre,
    numPostPeriods = post
  )
  original$Mbar <- 0
  sensitivity <- HonestDiD::createSensitivityResults(
    betahat = beta,
    sigma = vcov,
    numPrePeriods = pre,
    numPostPeriods = post,
    Mvec = seq(0.05, m_max, by = 0.2),
    l_vec = rep(1 / post, post),
    parallel = FALSE
  )
  plot <- HonestDiD::createSensitivityPlot(sensitivity, original) +
    labs(y = "Effect on Fires (1,000 units)", title = "") +
    theme_classic(base_size = 12) +
    theme(legend.position = "none")
  path <- file.path(figure_dir, paste0(file_base, suffix, ".png"))
  ggsave(path, plot = plot, width = 8, height = 4, dpi = 300)
  message("Generated: ", path)
}

plot_event <- function(event_data, file_base, num_pre, num_post,
                       omitted = -1, xlab = "Time from Treatment",
                       ylim_original = NULL, ylim_rotated = NULL) {
  event_data <- as.data.table(copy(event_data))
  setnames(event_data, names(event_data)[1:2], c("ymean", "beta"))
  event_data[, beta := as.numeric(beta)]
  dep_mean <- mean(as.numeric(event_data$ymean), na.rm = TRUE)
  vcov <- as.matrix(event_data[, -(1:2)])
  storage.mode(vcov) <- "double"
  if (nrow(vcov) != ncol(vcov) || nrow(vcov) != nrow(event_data)) {
    stop(file_base, ": coefficient and covariance dimensions differ")
  }
  event_data[, se := sqrt(diag(vcov))]

  if (omitted == -1) {
    event_data[, time := c(seq(-num_pre, -2), seq(0, num_post - 1))]
    full <- rbind(
      event_data[, .(time, beta, se)],
      data.table(time = -1, beta = 0, se = 0)
    )
    pre_idx <- seq_len(num_pre - 1)
    post_idx <- num_pre:(num_pre + num_post - 1)
    honest_pre <- num_pre - 1
  } else if (omitted == 0) {
    event_data[, time := c(seq(-num_pre, -1), seq(1, num_post))]
    full <- rbind(
      event_data[, .(time, beta, se)],
      data.table(time = 0, beta = 0, se = 0)
    )
    pre_idx <- seq_len(num_pre)
    post_idx <- (num_pre + 1):(num_pre + num_post)
    honest_pre <- num_pre
  } else {
    stop("Only omitted periods -1 and 0 are supported")
  }

  setorder(full, time)
  full[, `:=`(lower = beta - 1.96 * se, upper = beta + 1.96 * se)]
  pre <- mean_test(event_data$beta, vcov, pre_idx)
  post <- mean_test(event_data$beta, vcov, post_idx)
  annotation <- sprintf(
    "Mean DV = %.3f\nPre Avg = %.3f (%.3f)\nPost Avg = %.3f (%.3f)",
    dep_mean, pre[["estimate"]], pre[["se"]], post[["estimate"]], post[["se"]]
  )

  plot_theme <- theme_classic(base_size = 12) +
    theme(
      panel.grid.major = element_line(colour = "grey85", linetype = "dashed"),
      panel.grid.minor = element_blank(),
      legend.position = "none"
    )
  original <- ggplot(full, aes(time, beta)) +
    geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#279FF5", alpha = 0.2) +
    geom_line(colour = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
    geom_vline(xintercept = omitted, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    scale_x_continuous(breaks = seq(min(full$time), max(full$time))) +
    labs(x = xlab, y = "Effect on Number of Fires (in 1,000 units)") +
    annotate(
      "text", x = -Inf, y = Inf, hjust = -0.1, vjust = 1.1,
      label = annotation, size = 4
    ) +
    plot_theme
  if (!is.null(ylim_original)) original <- original + coord_cartesian(ylim = ylim_original)
  original_path <- file.path(figure_dir, paste0(file_base, "_ori.png"))
  ggsave(original_path, original, width = 8, height = 4, dpi = 300)
  message("Generated: ", original_path)

  full[, shifted_time := time - omitted]
  pretrend <- lm(beta ~ shifted_time - 1, data = full[shifted_time <= 0])
  full[, rotated := beta - predict(pretrend, newdata = full)]
  full[, `:=`(
    lower_rot = rotated - 1.96 * se,
    upper_rot = rotated + 1.96 * se
  )]
  rotated_plot <- ggplot(full, aes(time, rotated)) +
    geom_ribbon(
      aes(ymin = lower_rot, ymax = upper_rot),
      fill = "#279FF5", alpha = 0.2
    ) +
    geom_line(colour = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
    geom_vline(xintercept = omitted, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    scale_x_continuous(breaks = seq(min(full$time), max(full$time))) +
    labs(x = xlab, y = "Detrended Effect on Number of Fires (in 1,000 units)") +
    annotate(
      "text", x = -Inf, y = Inf, hjust = -0.1, vjust = 1.1,
      label = annotation, size = 4
    ) +
    plot_theme
  if (!is.null(ylim_rotated)) {
    rotated_plot <- rotated_plot + coord_cartesian(ylim = ylim_rotated)
  }
  rotated_path <- file.path(figure_dir, paste0(file_base, "_rotated.png"))
  ggsave(rotated_path, rotated_plot, width = 8, height = 4, dpi = 300)
  message("Generated: ", rotated_path)

  if (isTRUE(generate_honest)) {
    save_honest(
      event_data$beta, vcov, file_base, "_honest2", honest_pre, num_post
    )
    rotated_beta <- full[time != omitted, rotated]
    save_honest(
      rotated_beta, vcov, file_base, "_rot_honest2", honest_pre, num_post
    )
  }
}

extract_event <- function(csv_name, model, rows, columns) {
  path <- file.path(table_dir, csv_name)
  if (!file.exists(path)) return(NULL)
  estimates <- fread(path)
  selected <- estimates[reg == model]
  if (max(rows) > nrow(selected) || max(columns) > ncol(selected)) {
    stop(csv_name, " / ", model, ": unexpected saved-estimate layout")
  }
  out <- selected[rows, columns, with = FALSE]
  # estsave_csv writes beta, ymean, then the requested covariance columns.
  # plot_event consumes ymean, beta, vcov, so swap the first two explicitly.
  out[, c(2L, 1L, seq.int(3L, ncol(out))), with = FALSE]
}

run_case <- function(csv, model, rows, columns, base, pre, post, omitted,
                     xlab, ylim_original = NULL, ylim_rotated = NULL,
                     required = TRUE) {
  event <- extract_event(csv, model, rows, columns)
  if (is.null(event)) {
    message <- paste0("Missing estimate file: ", file.path(table_dir, csv))
    if (required) stop(message, call. = FALSE)
    warning("Skipping ", message, call. = FALSE)
    return(invisible(FALSE))
  }
  plot_event(event, base, pre, post, omitted, xlab,
             ylim_original, ylim_rotated)
  invisible(TRUE)
}

event_case <- function(id, csv_stem, model, rows, columns, figure_base,
                       pre, post, omitted = -1,
                       xlab = "Time from Treatment (months)",
                       ylim_original = NULL, ylim_rotated = NULL,
                       required = TRUE) {
  list(
    id = id,
    csv_stem = csv_stem,
    model = model,
    rows = rows,
    columns = columns,
    figure_base = figure_base,
    pre = pre,
    post = post,
    omitted = omitted,
    xlab = xlab,
    ylim_original = ylim_original,
    ylim_rotated = ylim_rotated,
    required = required
  )
}

run_registered_case <- function(spec, sample_suffix) {
  message("Running registered result: ", spec$id)
  run_case(
    csv = paste0(spec$csv_stem, sample_suffix, "_rural.csv"),
    model = spec$model,
    rows = spec$rows,
    columns = spec$columns,
    base = paste0(spec$figure_base, sample_suffix),
    pre = spec$pre,
    post = spec$post,
    omitted = spec$omitted,
    xlab = spec$xlab,
    ylim_original = spec$ylim_original,
    ylim_rotated = spec$ylim_rotated,
    required = spec$required
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
generate_honest <- args$honest
table_dir <- file.path(args$output_root, "tables")
figure_dir <- file.path(args$output_root, "figures")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
s <- args$sample

# --------------------------- RESULT REGISTRY ----------------------------
# To add a result, copy one event_case() block and change:
#   id, csv_stem, model, rows, columns, and figure_base.
# csv_stem excludes the optional sample suffix and trailing "_rural.csv".
event_cases <- list(
  # event_case(
  #   id = "legacy_main_baseline",
  #   csv_stem = "main_event_study", model = "evreg1",
  #   rows = c(6:1, 7:12), columns = c(3, 4, 10:5, 11:16),
  #   figure_base = "main_event_study_rural_1",
  #   pre = 6, post = 6, omitted = 0,
  #   ylim_original = c(-30, 20), ylim_rotated = c(-40, 30),
  #   required = FALSE
  # ),
  # event_case(
  #   id = "legacy_main_rice",
  #   csv_stem = "main_event_study", model = "evreg4",
  #   rows = c(18:13, 19:24), columns = c(3, 4, 22:17, 23:28),
  #   figure_base = "main_event_study_rural_riceP",
  #   pre = 6, post = 6, omitted = 0,
  #   ylim_original = c(-80, 50), ylim_rotated = c(-80, 50),
  #   required = FALSE
  # ),
  # event_case(
  #   id = "stacked_area_baseline",
  #   csv_stem = "stacked_event_study_5pre", model = "evreg1",
  #   rows = 15:25, columns = c(3, 4, 19:29),
  #   figure_base = "stacked_event_study_5pre_rural_1",
  #   pre = 6, post = 6,
  #   ylim_original = c(-40, 20), ylim_rotated = c(-40, 30)
  # ),
  # event_case(
  #   id = "stacked_population_baseline",
  #   csv_stem = "stacked_event_study_pop_5pre", model = "evreg1",
  #   rows = 15:25, columns = c(3, 4, 19:29),
  #   figure_base = "stacked_event_study_pop_5pre_rural_1",
  #   pre = 6, post = 6,
  #   ylim_original = c(-40, 20), ylim_rotated = c(-40, 30)
  # ),
  # event_case(
  #   id = "stacked_population_rice",
  #   csv_stem = "stacked_event_study_pop_5pre", model = "evreg2",
  #   rows = 39:49, columns = c(3, 4, 43:53),
  #   figure_base = "stacked_event_study_pop_5pre_rural_riceP",
  #   pre = 6, post = 6,
  #   ylim_original = c(-80, 50), ylim_rotated = c(-80, 50)
  # ),
  #
  # # Latest specification: grid x cohort and month-year x cohort FEs only.
  # event_case(
  #   id = "grid_monthyear_area_baseline",
  #   csv_stem = "stacked_event_study_5pre_grid_monthyear_fe",
  #   model = "evreg1", rows = 15:25, columns = c(3, 4, 19:29),
  #   figure_base = "stacked_event_study_5pre_grid_monthyear_fe_rural_1",
  #   pre = 6, post = 6
  # ),
  # event_case(
  #   id = "grid_monthyear_area_rice",
  #   csv_stem = "stacked_event_study_5pre_grid_monthyear_fe",
  #   model = "evreg2", rows = 39:49, columns = c(3, 4, 43:53),
  #   figure_base = "stacked_event_study_5pre_grid_monthyear_fe_rural_riceP",
  #   pre = 6, post = 6
  # ),
  # event_case(
  #   id = "grid_monthyear_population_baseline",
  #   csv_stem = "stacked_event_study_pop_5pre_grid_monthyear_fe",
  #   model = "evreg1", rows = 15:25, columns = c(3, 4, 19:29),
  #   figure_base = "stacked_event_study_pop_5pre_grid_monthyear_fe_rural_1",
  #   pre = 6, post = 6
  # ),
  # event_case(
  #   id = "grid_monthyear_population_rice",
  #   csv_stem = "stacked_event_study_pop_5pre_grid_monthyear_fe",
  #   model = "evreg2", rows = 39:49, columns = c(3, 4, 43:53),
  #   figure_base = "stacked_event_study_pop_5pre_grid_monthyear_fe_rural_riceP",
  #   pre = 6, post = 6
  # ),

  # Robustness 1: no controls; grid and month-year two-way clustering.
  event_case(
    id = "gm_pop_nocontrols_gridmonth_cluster_baseline",
    csv_stem = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "nocontrols_gridmonth_cluster"
    ),
    model = "evreg1", rows = 13:23, columns = c(3, 4, 17:27),
    figure_base = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "nocontrols_gridmonth_cluster_rural_1"
    ),
    pre = 6, post = 6, required = FALSE
  ),
  event_case(
    id = "gm_pop_nocontrols_gridmonth_cluster_rice",
    csv_stem = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "nocontrols_gridmonth_cluster"
    ),
    model = "evreg2", rows = 37:47, columns = c(3, 4, 41:51),
    figure_base = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "nocontrols_gridmonth_cluster_rural_riceP"
    ),
    pre = 6, post = 6, required = FALSE
  ),

  # Robustness 2: no controls; original cohort-interacted clustering.
  event_case(
    id = "gm_pop_nocontrols_cohort_cluster_baseline",
    csv_stem = "stacked_event_study_pop_5pre_grid_monthyear_fe_nocontrols",
    model = "evreg1", rows = 13:23, columns = c(3, 4, 17:27),
    figure_base = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "nocontrols_rural_1"
    ),
    pre = 6, post = 6, required = FALSE
  ),
  event_case(
    id = "gm_pop_nocontrols_cohort_cluster_rice",
    csv_stem = "stacked_event_study_pop_5pre_grid_monthyear_fe_nocontrols",
    model = "evreg2", rows = 37:47, columns = c(3, 4, 41:51),
    figure_base = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "nocontrols_rural_riceP"
    ),
    pre = 6, post = 6, required = FALSE
  ),

  # Robustness 3: controls retained; grid/month-year two-way clustering.
  event_case(
    id = "gm_pop_controls_gridmonth_cluster_baseline",
    csv_stem = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "gridmonth_cluster"
    ),
    model = "evreg1", rows = 15:25, columns = c(3, 4, 19:29),
    figure_base = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "gridmonth_cluster_rural_1"
    ),
    pre = 6, post = 6, required = FALSE
  ),
  event_case(
    id = "gm_pop_controls_gridmonth_cluster_rice",
    csv_stem = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "gridmonth_cluster"
    ),
    model = "evreg2", rows = 39:49, columns = c(3, 4, 43:53),
    figure_base = paste0(
      "stacked_event_study_pop_5pre_grid_monthyear_fe_",
      "gridmonth_cluster_rural_riceP"
    ),
    pre = 6, post = 6, required = FALSE
  )
)
# -----------------------------------------------------------------------

selected_event_cases <- event_cases
if (length(args$cases)) {
  known_case_ids <- vapply(event_cases, `[[`, character(1L), "id")
  unknown_case_ids <- setdiff(args$cases, known_case_ids)
  if (length(unknown_case_ids)) {
    stop(
      "Unknown main-result registry ID: ",
      paste(unknown_case_ids, collapse = ", "),
      call. = FALSE
    )
  }
  selected_event_cases <- event_cases[known_case_ids %in% args$cases]
}

if ("main" %in% args$families) {
  invisible(lapply(
    selected_event_cases, run_registered_case, sample_suffix = s
  ))
}

# All politician/protest moderators, area/population definitions, and controls.
control_suffixes <- c(never = "", both = "_controls_both", notyet = "_controls_notyet")
moderator_names <- c("1", "downup_2", "riceA_3", "riceHA_4", "riceP_5")

for (analysis_suffix in c("", "_acpop")) {
  for (control_suffix in unname(control_suffixes)) {
    politician_stem <- paste0(
      "_app_16_polischar_fe12_evst_all", s, "_rural",
      analysis_suffix, control_suffix
    )
    protest_stem <- paste0(
      "_app_17_5km_fe12_evst_all", s, "_rural",
      analysis_suffix, control_suffix
    )
    for (model_index in seq_along(moderator_names)) {
      if (model_index == 1L) {
        rows <- 13:21
        columns <- c(3, 4, 17:25)
      } else {
        rows <- 33:41
        columns <- c(3, 4, 37:45)
      }
      if ("politician" %in% args$families) {
        run_case(
          paste0(politician_stem, ".csv"), paste0("evreg", model_index),
          rows, columns,
          paste0(politician_stem, "_", moderator_names[[model_index]]),
          5, 5, -1, "Time from Treatment (years)",
          if (model_index == 1L) c(-20, 50) else NULL, NULL,
          required = identical(control_suffix, "")
        )
      }
      if ("protest" %in% args$families) {
        run_case(
          paste0(protest_stem, ".csv"), paste0("evreg", model_index),
          rows, columns,
          paste0(protest_stem, "_", moderator_names[[model_index]]),
          8, 2, -1, "Time from Treatment (years)",
          required = identical(control_suffix, "")
        )
      }
    }
  }
}

if (isTRUE(generate_honest)) {
  message("All requested event-study and HonestDiD plots completed.")
} else {
  message("All requested original and detrended event-study plots completed.")
}
