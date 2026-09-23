#!/usr/bin/env Rscript

# Generate every event-study figure actively referenced by _report/main.tex.
# The row/column selections reproduce the original plotting_event_studies.R
# files, while paths and execution are consolidated into this one entry point.

suppressPackageStartupMessages({
  library(data.table)
  library(doParallel)
  library(ggplot2)
  library(HonestDiD)
})

parse_args <- function(args) {
  out <- list(root = Sys.getenv("REPLICATION_ROOT", unset = ""))
  i <- 1L
  while (i <= length(args)) {
    if (args[[i]] == "--root" && i < length(args)) {
      out$root <- args[[i + 1L]]
      i <- i + 2L
    } else {
      stop("Unknown or incomplete argument: ", args[[i]])
    }
  }
  if (!nzchar(out$root)) stop("Supply --root PATH or set REPLICATION_ROOT")
  out
}

mean_test <- function(beta, V, idx) {
  w <- rep(1 / length(idx), length(idx))
  b <- beta[idx]
  VV <- V[idx, idx, drop = FALSE]
  c(estimate = sum(w * b), se = sqrt(drop(t(w) %*% VV %*% w)))
}

save_sensitivity <- function(beta, V, file_base, suffix, pre, post, M = 1) {
  original <- HonestDiD::constructOriginalCS(
    betahat = beta, sigma = V, numPrePeriods = pre, numPostPeriods = post
  )
  original$Mbar <- 0
  result <- HonestDiD::createSensitivityResults(
    betahat = beta,
    sigma = V,
    numPrePeriods = pre,
    numPostPeriods = post,
    Mvec = seq(0.05, M, by = 0.2),
    l_vec = rep(1 / post, post),
    parallel = use_parallel
  )
  plot <- HonestDiD::createSensitivityPlot(result, original) +
    labs(y = "Effect on Fires (1,000 units)", title = "") +
    theme_classic(base_size = 12) +
    theme(legend.position = "none")
  path <- file.path(figure_dir, paste0(file_base, suffix, ".png"))
  ggsave(path, plot = plot, width = 8, height = 4, dpi = 300)
  message("Generated: ", path)
}

plot_event <- function(ev, file_base, num_pre, num_post, omitted = -1,
                       ylim_original = NULL, ylim_rotated = NULL, honest = TRUE) {
  ev <- as.data.table(copy(ev))
  setnames(ev, names(ev)[1:2], c("ymean", "beta"))
  ev[, beta := as.numeric(beta)]
  ymean <- mean(as.numeric(ev$ymean), na.rm = TRUE)
  V <- as.matrix(ev[, -(1:2)])
  storage.mode(V) <- "double"
  if (nrow(V) != ncol(V) || nrow(V) != nrow(ev)) {
    stop(file_base, ": coefficient/covariance dimensions do not agree")
  }
  ev[, se := sqrt(diag(V))]

  if (omitted == -1) {
    ev[, time := c(seq(-num_pre, -2), seq(0, num_post - 1))]
    full <- rbind(ev[, .(time, beta, se)], data.table(time = -1, beta = 0, se = 0))
    pre_idx <- seq_len(num_pre - 1)
    post_idx <- num_pre:(num_pre + num_post - 1)
    honest_pre <- num_pre - 1
  } else if (omitted == 0) {
    ev[, time := c(seq(-num_pre, -1), seq(1, num_post))]
    full <- rbind(ev[, .(time, beta, se)], data.table(time = 0, beta = 0, se = 0))
    pre_idx <- seq_len(num_pre)
    post_idx <- (num_pre + 1):(num_pre + num_post)
    honest_pre <- num_pre
  } else {
    stop("omitted must be -1 or 0")
  }
  setorder(full, time)
  full[, `:=`(lower = beta - 1.96 * se, upper = beta + 1.96 * se)]

  pre <- mean_test(ev$beta, V, pre_idx)
  post <- mean_test(ev$beta, V, post_idx)
  annotation <- sprintf(
    "Mean DV = %.3f\nPre Avg = %.3f (%.3f)\nPost Avg = %.3f (%.3f)",
    ymean, pre[["estimate"]], pre[["se"]], post[["estimate"]], post[["se"]]
  )
  common_theme <- theme(
    panel.background = element_rect(fill = "white", colour = NA),
    plot.background = element_rect(fill = "white", colour = NA),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(colour = "grey85", linetype = "dashed"),
    axis.line = element_line(colour = "black"),
    legend.position = "none"
  )
  original_plot <- ggplot(full, aes(time, beta)) +
    geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#279FF5", alpha = 0.2) +
    geom_line(colour = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
    geom_vline(xintercept = omitted, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    scale_x_continuous(breaks = seq(min(full$time), max(full$time))) +
    labs(x = "Time from Treatment (months)",
         y = "Effect on Number of Fires (in 1,000 units)") +
    annotate("text", x = -Inf, y = Inf, hjust = -0.1, vjust = 1.1,
             label = annotation, size = 4) + common_theme
  if (!is.null(ylim_original)) original_plot <- original_plot + coord_cartesian(ylim = ylim_original)
  original_path <- file.path(figure_dir, paste0(file_base, "_ori.png"))
  ggsave(original_path, original_plot, width = 8, height = 4, dpi = 300)
  message("Generated: ", original_path)

  full[, shifted_time := time - omitted]
  trend <- lm(beta ~ shifted_time - 1, data = full[shifted_time <= 0])
  full[, rotated := beta - predict(trend, newdata = full)]
  full[, `:=`(lower_rot = rotated - 1.96 * se, upper_rot = rotated + 1.96 * se)]
  rotated_plot <- ggplot(full, aes(time, rotated)) +
    geom_ribbon(aes(ymin = lower_rot, ymax = upper_rot), fill = "#279FF5", alpha = 0.2) +
    geom_line(colour = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
    geom_vline(xintercept = omitted, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    scale_x_continuous(breaks = seq(min(full$time), max(full$time))) +
    labs(x = "Time from Treatment (months)",
         y = "Effect on Number of Fires (in 1,000 units)") +
    annotate("text", x = -Inf, y = Inf, hjust = -0.1, vjust = 1.1,
             label = annotation, size = 4) + common_theme
  if (!is.null(ylim_rotated)) rotated_plot <- rotated_plot + coord_cartesian(ylim = ylim_rotated)
  rotated_path <- file.path(figure_dir, paste0(file_base, "_rotated.png"))
  ggsave(rotated_path, rotated_plot, width = 8, height = 4, dpi = 300)
  message("Generated: ", rotated_path)

  if (honest) {
    rotated_beta <- full[time != omitted, rotated]
    save_sensitivity(ev$beta, V, file_base, "_honest2", honest_pre, num_post)
    save_sensitivity(rotated_beta, V, file_base, "_rot_honest2", honest_pre, num_post)
  }
}

extract_event <- function(csv_name, model, rows, columns) {
  path <- file.path(table_dir, csv_name)
  if (!file.exists(path)) stop("Required event-study estimates not found: ", path)
  data <- fread(path)
  selected <- data[reg == model]
  if (max(rows) > nrow(selected) || max(columns) > ncol(selected)) {
    stop(csv_name, " / ", model, ": saved-estimate layout differs from the expected layout")
  }
  selected[rows, columns, with = FALSE]
}

run_case <- function(csv, model, rows, cols, base, pre, post, omitted,
                     ylim_original = NULL, ylim_rotated = NULL) {
  plot_event(
    extract_event(csv, model, rows, cols), base, pre, post, omitted,
    ylim_original = ylim_original, ylim_rotated = ylim_rotated, honest = TRUE
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
table_dir <- file.path(args$root, "tex", "paper", "tables")
figure_dir <- file.path(args$root, "tex", "paper", "figures")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

requested_cores <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "1")))
if (is.na(requested_cores) || requested_cores < 1) requested_cores <- 1L
cluster <- NULL
use_parallel <- requested_cores > 1L
if (use_parallel) {
  cluster <- parallel::makeCluster(requested_cores)
  doParallel::registerDoParallel(cluster)
} else {
  foreach::registerDoSEQ()
}

# Main area event study.
run_case("main_event_study_rural.csv", "evreg1", c(6:1, 7:12),
         c(3, 4, 10:5, 11:16), "main_event_study_rural_1", 6, 6, 0,
         c(-30, 20), c(-40, 30))
run_case("main_event_study_rural.csv", "evreg4", c(18:13, 19:24),
         c(3, 4, 22:17, 23:28), "main_event_study_rural_riceP", 6, 6, 0,
         c(-80, 50), c(-80, 50))

# Five-pre-period stacked event studies (area and population treatment).
run_case("stacked_event_study_5pre_rural.csv", "evreg1", 15:25,
         c(3, 4, 19:29), "stacked_event_study_5pre_rural_1", 5, 7, -1,
         c(-40, 20), c(-40, 30))
run_case("stacked_event_study_pop_5pre_rural.csv", "evreg1", 15:25,
         c(3, 4, 19:29), "stacked_event_study_pop_5pre_rural_1", 5, 7, -1,
         c(-40, 20), c(-40, 30))
run_case("stacked_event_study_pop_5pre_rural.csv", "evreg2", 39:49,
         c(3, 4, 43:53), "stacked_event_study_pop_5pre_rural_riceP", 5, 7, -1,
         c(-80, 50), c(-80, 50))

# Politician and protest event studies, for area and population definitions.
for (suffix in c("", "_acpop")) {
  run_case(paste0("_app_16_polischar_fe12_evst_all_rural", suffix, ".csv"),
           "evreg1", 13:21, c(3, 4, 17:25),
           paste0("_app_16_polischar_fe12_evst_all_rural", suffix, "_1"),
           5, 5, -1, c(-20, 50), NULL)
  run_case(paste0("_app_16_polischar_fe12_evst_all_rural", suffix, ".csv"),
           "evreg5", 33:41, c(3, 4, 37:45),
           paste0("_app_16_polischar_fe12_evst_all_rural", suffix, "_riceP_5"),
           5, 5, -1)
  run_case(paste0("_app_17_5km_fe12_evst_all_rural", suffix, ".csv"),
           "evreg1", 13:21, c(3, 4, 17:25),
           paste0("_app_17_5km_fe12_evst_all_rural", suffix, "_1"),
           8, 2, -1)
}

if (!is.null(cluster)) parallel::stopCluster(cluster)
message("Event-study plotting completed.")
