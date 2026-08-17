#!/usr/bin/env Rscript

# Render original and detrended event-study plots in the established format.
suppressPackageStartupMessages({library(data.table); library(ggplot2)})
data.table::setDTthreads(1L)

cfg <- list(
  root = "/users/aquisper/proj_bureaucrats_farms",
  analysis = "",
  first = NA_integer_,
  last = NA_integer_
)
args <- commandArgs(trailingOnly = TRUE)
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--root" && i < length(args)) {
    cfg$root <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--analysis" && i < length(args)) {
    cfg$analysis <- args[[i + 1L]]; i <- i + 2L
  } else if (args[[i]] == "--first" && i < length(args)) {
    cfg$first <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (args[[i]] == "--last" && i < length(args)) {
    cfg$last <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else stop("Unknown or incomplete argument: ", args[[i]])
}
if (!cfg$analysis %in% c("politician", "protest")) stop("Invalid analysis.")
if (anyNA(c(cfg$first, cfg$last)) || cfg$first < 1L || cfg$last > 32L || cfg$first > cfg$last) {
  stop("Invalid FE range.")
}

rel <- file.path("exploratory_analysis", "cohort_eventtime_fe_sweep")
table_dir <- file.path(cfg$root, "tables", rel)
figure_dir <- file.path(cfg$root, "figures", rel)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

mean_test <- function(beta, vcov, idx) {
  w <- rep(1 / length(idx), length(idx))
  c(estimate = sum(w * beta[idx]),
    se = sqrt(drop(t(w) %*% vcov[idx, idx, drop = FALSE] %*% w)))
}

read_event <- function(path) {
  x <- fread(path)[reg == "evreg1"]
  if (nrow(x) < 21L || ncol(x) < 25L) stop(basename(path), ": unexpected layout")
  out <- x[13:21, c(3, 4, 17:25), with = FALSE]
  out[, c(2L, 1L, 3:ncol(out)), with = FALSE]
}

render_event <- function(event_data, stem, times, x_label) {
  setnames(event_data, names(event_data)[1:2], c("ymean", "beta"))
  event_data[, beta := as.numeric(beta)]
  vcov <- as.matrix(event_data[, -(1:2)])
  storage.mode(vcov) <- "double"
  if (!identical(dim(vcov), c(9L, 9L))) stop(stem, ": expected a 9x9 covariance matrix")
  pre_idx <- which(times < -1L)
  post_idx <- which(times >= 0L)
  event_data[, `:=`(time = times, se = sqrt(diag(vcov)))]
  full <- rbind(event_data[, .(time, beta, se)],
                data.table(time = -1L, beta = 0, se = 0))
  setorder(full, time)
  dep_mean <- mean(as.numeric(event_data$ymean), na.rm = TRUE)
  original_pre <- mean_test(event_data$beta, vcov, pre_idx)
  original_post <- mean_test(event_data$beta, vcov, post_idx)

  shifted <- times + 1L
  slope_weights <- numeric(length(times))
  slope_weights[pre_idx] <- shifted[pre_idx] / sum(shifted[pre_idx]^2)
  rotation <- diag(length(times)) - outer(shifted, slope_weights)
  rotated_beta <- drop(rotation %*% event_data$beta)
  rotated_vcov <- rotation %*% vcov %*% t(rotation)
  rotated_pre <- mean_test(rotated_beta, rotated_vcov, pre_idx)
  rotated_post <- mean_test(rotated_beta, rotated_vcov, post_idx)
  full[time != -1L, rotated := rotated_beta]
  full[time == -1L, rotated := 0]
  full[, `:=`(
    lower = beta - 1.96 * se,
    upper = beta + 1.96 * se,
    lower_rot = rotated - 1.96 * se,
    upper_rot = rotated + 1.96 * se
  )]

  theme_event <- theme_classic(base_size = 12) + theme(
    panel.grid.major = element_line(colour = "grey85", linetype = "dashed"),
    panel.grid.minor = element_blank(), legend.position = "none"
  )
  make_plot <- function(y, lower, upper, pre, post, ylabel, suffix) {
    span <- diff(range(c(full[[lower]], full[[upper]]), na.rm = TRUE))
    if (!is.finite(span) || span == 0) span <- 1
    annotations <- data.table(
      time = min(full$time),
      value = max(full[[upper]], na.rm = TRUE) - (0:2) * span * .07,
      label = c(
        sprintf("Mean DV = %.3f", dep_mean),
        sprintf("Pre Avg = %.3f (%.3f)", pre[["estimate"]], pre[["se"]]),
        sprintf("Post Avg = %.3f (%.3f)", post[["estimate"]], post[["se"]])
      )
    )
    plot <- ggplot(full, aes(x = time, y = .data[[y]])) +
      geom_ribbon(aes(ymin = .data[[lower]], ymax = .data[[upper]]),
                  fill = "#279FF5", alpha = .2) +
      geom_line(colour = "#279FF5", linewidth = .8) +
      geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
      geom_vline(xintercept = -1, linetype = "dashed", colour = "blue") +
      geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
      scale_x_continuous(breaks = min(full$time):max(full$time)) +
      geom_text(data = annotations, aes(time, value, label = label),
                inherit.aes = FALSE, hjust = 0, vjust = 1, size = 4) +
      labs(x = x_label, y = ylabel) + theme_event
    output <- file.path(figure_dir, paste0(stem, suffix, ".png"))
    ggsave(output, plot, width = 8, height = 4, dpi = 300)
    message("Generated: ", output)
  }
  make_plot("beta", "lower", "upper", original_pre, original_post,
            "Effect on Number of Fires (in 1,000 units)", "_ori")
  make_plot("rotated", "lower_rot", "upper_rot", rotated_pre, rotated_post,
            "Detrended Effect on Fires (in 1,000 units)", "_rotated")
}

if (cfg$analysis == "politician") {
  prefix <- "politician_byprov_cohorttime_fe"
  times <- c(-5:-2, 0:4)
  x_label <- "Years from Election"
} else {
  prefix <- "protest_never_cohorttime_fe"
  times <- c(-8:-2, 0:1)
  x_label <- "Years from Protest"
}

for (fe in cfg$first:cfg$last) {
  stem <- paste0(prefix, sprintf("%02d", fe), "_event_rural_acpop_all")
  csv <- file.path(table_dir, paste0(stem, ".csv"))
  if (!file.exists(csv)) stop("Missing event CSV: ", csv)
  render_event(read_event(csv), stem, times, x_label)
}
message("Completed ", cfg$analysis, " FE ", cfg$first, "-", cfg$last, " plots.")

