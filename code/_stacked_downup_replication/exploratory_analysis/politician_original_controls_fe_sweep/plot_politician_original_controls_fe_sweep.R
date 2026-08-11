#!/usr/bin/env Rscript

# Render the original-dataset, three-control-sample FE sweep using the visual
# format established in plotting_event_studies.R. This is a separate renderer;
# the original plotting script is not sourced or modified.

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})
data.table::setDTthreads(1L)

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
detected_root <- find_repo(if (nzchar(script_path)) script_path else getwd())
RSTUDIO_CONFIG <- list(
  root = detected_root,
  output_root = detected_root,
  controls = c("never", "both", "notyet"),
  fe_ids = 1:32,
  sample = FALSE
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
    } else if (args[[i]] == "--controls" && i < length(args)) {
      out$controls <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
    } else if (args[[i]] == "--fe-list" && i < length(args)) {
      out$fe_ids <- as.integer(trimws(
        strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]
      ))
      i <- i + 2L
    } else if (args[[i]] == "--sample") {
      out$sample <- TRUE
      i <- i + 1L
    } else {
      stop("Unknown or incomplete argument: ", args[[i]], call. = FALSE)
    }
  }
  if (!nzchar(out$root) || !nzchar(out$output_root)) {
    stop("Set repository paths or provide --root and --output-root.")
  }
  invalid_controls <- setdiff(out$controls, c("never", "both", "notyet"))
  if (length(invalid_controls)) {
    stop("Unknown controls: ", paste(invalid_controls, collapse = ", "))
  }
  if (anyNA(out$fe_ids) || any(!out$fe_ids %in% 1:32)) {
    stop("FE ids must be integers from 1 through 32.")
  }
  out$root <- normalizePath(out$root, winslash = "/", mustWork = FALSE)
  out$output_root <- normalizePath(
    out$output_root, winslash = "/", mustWork = FALSE
  )
  out
}

cfg <- parse_args(commandArgs(trailingOnly = TRUE))
relative_dir <- file.path(
  "exploratory_analysis", "politician_original_controls_fe_sweep"
)
if (isTRUE(cfg$sample)) relative_dir <- file.path(relative_dir, "sample")
table_dir <- file.path(cfg$root, "tables", relative_dir)
figure_dir <- file.path(cfg$output_root, "figures", relative_dir)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

mean_test <- function(beta, vcov, indices) {
  weights <- rep(1 / length(indices), length(indices))
  selected_vcov <- vcov[indices, indices, drop = FALSE]
  c(
    estimate = mean(beta[indices]),
    se = sqrt(drop(t(weights) %*% selected_vcov %*% weights))
  )
}

extract_event <- function(path) {
  estimates <- fread(path)
  selected <- estimates[reg == "evreg1"]
  rows <- 13:21
  columns <- c(3, 4, 17:25)
  if (max(rows) > nrow(selected) || max(columns) > ncol(selected)) {
    stop(basename(path), ": unexpected estsave_csv layout")
  }
  out <- selected[rows, columns, with = FALSE]
  out[, c(2L, 1L, seq.int(3L, ncol(out))), with = FALSE]
}

plot_event <- function(event_data, file_base, fe_id, control_sample) {
  event_data <- as.data.table(copy(event_data))
  setnames(event_data, names(event_data)[1:2], c("ymean", "beta"))
  event_data[, beta := as.numeric(beta)]
  vcov <- as.matrix(event_data[, -(1:2)])
  storage.mode(vcov) <- "double"
  if (!identical(dim(vcov), c(9L, 9L))) {
    stop(file_base, ": expected nine coefficients and a 9x9 covariance")
  }

  event_data[, `:=`(
    se = sqrt(diag(vcov)),
    time = c(-5:-2, 0:4)
  )]
  full <- rbind(
    event_data[, .(time, beta, se)],
    data.table(time = -1L, beta = 0, se = 0)
  )
  setorder(full, time)
  pre_idx <- 1:4
  post_idx <- 5:9
  dep_mean <- mean(as.numeric(event_data$ymean), na.rm = TRUE)

  original_pre <- mean_test(event_data$beta, vcov, pre_idx)
  original_post <- mean_test(event_data$beta, vcov, post_idx)
  original_labels <- c(
    sprintf("Mean DV = %.3f", dep_mean),
    sprintf(
      "Pre Avg = %.3f (%.3f)",
      original_pre[["estimate"]], original_pre[["se"]]
    ),
    sprintf(
      "Post Avg = %.3f (%.3f)",
      original_post[["estimate"]], original_post[["se"]]
    )
  )

  full[, `:=`(
    lower = beta - 1.96 * se,
    upper = beta + 1.96 * se
  )]
  original_range <- diff(range(c(full$lower, full$upper), na.rm = TRUE))
  if (!is.finite(original_range) || original_range == 0) original_range <- 1
  original_annotation <- data.table(
    time = min(full$time),
    value = max(full$upper, na.rm = TRUE) - (0:2) * original_range * 0.07,
    label = original_labels
  )

  plot_theme <- theme_classic(base_size = 12) +
    theme(
      panel.grid.major = element_line(colour = "grey85", linetype = "dashed"),
      panel.grid.minor = element_blank(),
      legend.position = "none"
    )

  original_plot <- ggplot(full, aes(time, beta)) +
    geom_ribbon(
      aes(ymin = lower, ymax = upper), fill = "#279FF5", alpha = 0.2
    ) +
    geom_line(colour = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
    geom_vline(xintercept = -1, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    scale_x_continuous(breaks = -5:4) +
    labs(
      x = "Years from Election",
      y = "Effect on Number of Fires (in 1,000 units)"
    ) +
    geom_text(
      data = original_annotation,
      aes(x = time, y = value, label = label),
      inherit.aes = FALSE, hjust = 0, vjust = 1, size = 4
    ) +
    plot_theme
  original_path <- file.path(figure_dir, paste0(file_base, "_ori.png"))
  ggsave(original_path, original_plot, width = 8, height = 4, dpi = 300)
  message("Generated: ", original_path)

  shifted_time <- event_data$time + 1
  slope_weights <- numeric(length(event_data$beta))
  slope_weights[pre_idx] <- shifted_time[pre_idx] /
    sum(shifted_time[pre_idx]^2)
  rotation <- diag(length(event_data$beta)) -
    outer(shifted_time, slope_weights)
  rotated_beta <- drop(rotation %*% event_data$beta)
  rotated_vcov <- rotation %*% vcov %*% t(rotation)
  rotated_pre <- mean_test(rotated_beta, rotated_vcov, pre_idx)
  rotated_post <- mean_test(rotated_beta, rotated_vcov, post_idx)
  rotated_labels <- c(
    sprintf("Mean DV = %.3f", dep_mean),
    sprintf(
      "Pre Avg = %.3f (%.3f)",
      rotated_pre[["estimate"]], rotated_pre[["se"]]
    ),
    sprintf(
      "Post Avg = %.3f (%.3f)",
      rotated_post[["estimate"]], rotated_post[["se"]]
    )
  )

  full[time != -1, rotated := rotated_beta]
  full[time == -1, rotated := 0]
  # Preserve the original plotting script's pointwise-CI convention: the
  # coefficient path is rotated, while pointwise bands retain the original SE.
  full[, `:=`(
    lower_rot = rotated - 1.96 * se,
    upper_rot = rotated + 1.96 * se
  )]
  rotated_range <- diff(
    range(c(full$lower_rot, full$upper_rot), na.rm = TRUE)
  )
  if (!is.finite(rotated_range) || rotated_range == 0) rotated_range <- 1
  rotated_annotation <- data.table(
    time = min(full$time),
    value = max(full$upper_rot, na.rm = TRUE) - (0:2) * rotated_range * 0.07,
    label = rotated_labels
  )
  rotated_plot <- ggplot(full, aes(time, rotated)) +
    geom_ribbon(
      aes(ymin = lower_rot, ymax = upper_rot),
      fill = "#279FF5", alpha = 0.2
    ) +
    geom_line(colour = "#279FF5", linewidth = 0.8) +
    geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
    geom_vline(xintercept = -1, linetype = "dashed", colour = "blue") +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
    scale_x_continuous(breaks = -5:4) +
    labs(
      x = "Years from Election",
      y = "Detrended Effect on Fires (in 1,000 units)"
    ) +
    geom_text(
      data = rotated_annotation,
      aes(x = time, y = value, label = label),
      inherit.aes = FALSE, hjust = 0, vjust = 1, size = 4
    ) +
    plot_theme
  rotated_path <- file.path(figure_dir, paste0(file_base, "_rotated.png"))
  ggsave(rotated_path, rotated_plot, width = 8, height = 4, dpi = 300)
  message("Generated: ", rotated_path)

  coefficient_summary <- rbind(
    data.table(
      fe_id = fe_id, control_sample = control_sample,
      version = "original", time = full$time, beta = full$beta,
      se = full$se, lower = full$lower, upper = full$upper
    ),
    data.table(
      fe_id = fe_id, control_sample = control_sample,
      version = "rotated", time = full$time, beta = full$rotated,
      se = full$se, lower = full$lower_rot, upper = full$upper_rot
    )
  )
  average_summary <- rbind(
    data.table(
      fe_id = fe_id, control_sample = control_sample,
      version = "original", period = c("pre", "post"),
      estimate = c(original_pre[["estimate"]], original_post[["estimate"]]),
      se = c(original_pre[["se"]], original_post[["se"]])
    ),
    data.table(
      fe_id = fe_id, control_sample = control_sample,
      version = "rotated", period = c("pre", "post"),
      estimate = c(rotated_pre[["estimate"]], rotated_post[["estimate"]]),
      se = c(rotated_pre[["se"]], rotated_post[["se"]])
    )
  )
  average_summary[, `:=`(
    lower = estimate - 1.96 * se,
    upper = estimate + 1.96 * se
  )]
  list(coefficients = coefficient_summary, averages = average_summary)
}

coefficient_results <- list()
average_results <- list()
result_index <- 1L
missing_inputs <- character()

for (control_sample in cfg$controls) {
  for (fe_id in cfg$fe_ids) {
    fe_tag <- sprintf("%02d", fe_id)
    stem <- paste0(
      "politician_original_fe", fe_tag,
      "_controls_", control_sample
    )
    csv_path <- file.path(
      table_dir, paste0(stem, "_event_rural_acpop_all.csv")
    )
    if (!file.exists(csv_path)) {
      missing_inputs <- c(missing_inputs, csv_path)
      next
    }
    event <- extract_event(csv_path)
    result <- plot_event(
      event, paste0(stem, "_event"), fe_id, control_sample
    )
    coefficient_results[[result_index]] <- result$coefficients
    average_results[[result_index]] <- result$averages
    result_index <- result_index + 1L
  }
}

if (length(missing_inputs)) {
  stop(
    "Missing ", length(missing_inputs), " event-study CSV file(s):\n",
    paste(missing_inputs, collapse = "\n"),
    call. = FALSE
  )
}

coefficients <- rbindlist(coefficient_results)
averages <- rbindlist(average_results)
fwrite(
  coefficients,
  file.path(table_dir, "politician_original_controls_coefficients.csv")
)
fwrite(
  averages,
  file.path(table_dir, "politician_original_controls_pre_post_averages.csv")
)
message("Completed 96 original and 96 rotated event-study figures.")
