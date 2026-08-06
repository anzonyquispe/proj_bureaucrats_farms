#!/usr/bin/env Rscript

# Single entry point for every event-study and HonestDiD plot produced by the
# stacked/down-up replication package. The politician and protest families are
# rendered for never-treated, pooled never/not-yet-treated, and not-yet-treated
# control samples. Baseline (never-treated) filenames remain unchanged.

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(HonestDiD)
})

parse_args <- function(args) {
  out <- list(
    root = Sys.getenv("REPLICATION_ROOT", unset = ""),
    sample = Sys.getenv("REPLICATION_SAMPLE", unset = "")
  )
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--root" && i < length(args)) {
      out$root <- args[[i + 1L]]
      i <- i + 2L
    } else if (args[[i]] == "--sample" && i < length(args)) {
      out$sample <- args[[i + 1L]]
      if (identical(out$sample, "none")) out$sample <- ""
      i <- i + 2L
    } else {
      stop("Unknown or incomplete argument: ", args[[i]])
    }
  }
  if (!nzchar(out$root)) stop("Supply --root PATH or set REPLICATION_ROOT")
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

  save_honest(event_data$beta, vcov, file_base, "_honest2", honest_pre, num_post)
  rotated_beta <- full[time != omitted, rotated]
  save_honest(rotated_beta, vcov, file_base, "_rot_honest2", honest_pre, num_post)
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

args <- parse_args(commandArgs(trailingOnly = TRUE))
table_dir <- file.path(args$root, "tex", "paper", "tables")
figure_dir <- file.path(args$root, "tex", "paper", "figures")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
s <- args$sample

# Main area and stacked down/up event studies.
run_case(
  paste0("main_event_study", s, "_rural.csv"), "evreg1",
  c(6:1, 7:12), c(3, 4, 10:5, 11:16),
  "main_event_study_rural_1", 6, 6, 0, "Time from Treatment (months)",
  c(-30, 20), c(-40, 30), required = FALSE
)
run_case(
  paste0("main_event_study", s, "_rural.csv"), "evreg4",
  c(18:13, 19:24), c(3, 4, 22:17, 23:28),
  "main_event_study_rural_riceP", 6, 6, 0,
  "Time from Treatment (months)", c(-80, 50), c(-80, 50),
  required = FALSE
)
run_case(
  paste0("stacked_event_study_5pre", s, "_rural.csv"), "evreg1",
  15:25, c(3, 4, 19:29), "stacked_event_study_5pre_rural_1",
  5, 7, -1, "Time from Treatment (months)", c(-40, 20), c(-40, 30)
)
run_case(
  paste0("stacked_event_study_pop_5pre", s, "_rural.csv"), "evreg1",
  15:25, c(3, 4, 19:29), "stacked_event_study_pop_5pre_rural_1",
  5, 7, -1, "Time from Treatment (months)", c(-40, 20), c(-40, 30)
)
run_case(
  paste0("stacked_event_study_pop_5pre", s, "_rural.csv"), "evreg2",
  39:49, c(3, 4, 43:53), "stacked_event_study_pop_5pre_rural_riceP",
  5, 7, -1, "Time from Treatment (months)", c(-80, 50), c(-80, 50)
)

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
      run_case(
        paste0(politician_stem, ".csv"), paste0("evreg", model_index),
        rows, columns, paste0(politician_stem, "_", moderator_names[[model_index]]),
        5, 5, -1, "Time from Treatment (years)",
        if (model_index == 1L) c(-20, 50) else NULL, NULL
      )
      run_case(
        paste0(protest_stem, ".csv"), paste0("evreg", model_index),
        rows, columns, paste0(protest_stem, "_", moderator_names[[model_index]]),
        8, 2, -1, "Time from Treatment (years)"
      )
    }
  }
}

message("All event-study and HonestDiD plots completed.")
