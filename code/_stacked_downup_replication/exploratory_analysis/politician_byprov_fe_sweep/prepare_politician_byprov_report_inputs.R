#!/usr/bin/env Rscript

# Prepare the numeric summaries and DiD interaction figures used by the
# politician-by-province FE-sweep report. This script does not estimate models:
# it reads the coefficient vectors and covariance matrices exported by Stata.

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
if (length(args)) {
  if (length(args) != 2L || args[[1L]] != "--root") {
    stop("Usage: Rscript prepare_politician_byprov_report_inputs.R [--root REPO]")
  }
  root <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
}

table_dir <- file.path(
  root, "tables", "exploratory_analysis", "politician_byprov_fe_sweep"
)
figure_dir <- file.path(
  root, "figures", "exploratory_analysis", "politician_byprov_fe_sweep"
)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

linear_result <- function(beta, vcov, weights, df, level = 0.95) {
  estimate <- sum(weights * beta)
  se <- sqrt(drop(t(weights) %*% vcov %*% weights))
  critical <- qt(1 - (1 - level) / 2, df = df)
  c(
    estimate = estimate,
    se = se,
    lower = estimate - critical * se,
    upper = estimate + critical * se
  )
}

mean_result <- function(beta, vcov, indices) {
  weights <- numeric(length(beta))
  weights[indices] <- 1 / length(indices)
  linear_result(beta, vcov, weights, df = Inf)
}

coefficient_rows <- list()
average_rows <- list()

for (fe_id in 1:32) {
  tag <- sprintf("%02d", fe_id)
  event_path <- file.path(
    table_dir,
    paste0("politician_byprov_fe", tag, "_event_rural_acpop_all.csv")
  )
  did_path <- file.path(
    table_dir,
    paste0("politician_byprov_fe", tag, "_did_interaction_rural_acpop_all.csv")
  )
  scalar_path <- sub("[.]csv$", "_scalars.csv", did_path)
  required <- c(event_path, did_path, scalar_path)
  missing <- required[!file.exists(required) | file.info(required)$size <= 0]
  if (length(missing)) {
    stop("Missing or empty FE ", fe_id, " input(s): ", paste(missing, collapse = ", "))
  }

  # The event-study treatment effects are rows 13:21 and covariance columns
  # cov13:cov21 in the established estsave_csv layout.
  event <- fread(event_path)[reg == "evreg1"]
  if (nrow(event) < 21L) stop("Unexpected event-study layout for FE ", fe_id)
  selected <- event[13:21]
  beta <- as.numeric(selected$beta)
  vcov <- as.matrix(selected[, paste0("cov", 13:21), with = FALSE])
  storage.mode(vcov) <- "double"
  times <- c(-5:-2, 0:4)
  ses <- sqrt(diag(vcov))

  shifted <- times + 1
  slope_weights <- numeric(length(beta))
  slope_weights[1:4] <- shifted[1:4] / sum(shifted[1:4]^2)
  rotation <- diag(length(beta)) - outer(shifted, slope_weights)
  rotated_beta <- drop(rotation %*% beta)
  rotated_vcov <- rotation %*% vcov %*% t(rotation)

  for (version in c("original", "rotated")) {
    current_beta <- if (version == "original") beta else rotated_beta
    # Match plotting_event_studies.R: pointwise rotated bands retain the
    # original coefficient standard errors, while averages propagate the
    # transformed covariance matrix.
    current_se <- ses
    coefficient_rows[[length(coefficient_rows) + 1L]] <- rbind(
      data.table(
        fe_id = fe_id, model = "baseline", version = version,
        time = times, beta = current_beta,
        lower = current_beta - 1.96 * current_se,
        upper = current_beta + 1.96 * current_se
      ),
      data.table(
        fe_id = fe_id, model = "baseline", version = version,
        time = -1L, beta = 0, lower = 0, upper = 0
      )
    )
    current_vcov <- if (version == "original") vcov else rotated_vcov
    for (period in c("pre", "post")) {
      indices <- if (period == "pre") 1:4 else 5:9
      result <- mean_result(current_beta, current_vcov, indices)
      average_rows[[length(average_rows) + 1L]] <- data.table(
        fe_id = fe_id, model = "baseline", version = version,
        period = period, estimate = result[["estimate"]],
        se = result[["se"]], lower = result[["lower"]],
        upper = result[["upper"]]
      )
    }
  }

  # Reproduce interaction_graph.ado's four linear combinations.
  did <- fread(did_path)[reg == "evreg1"]
  did_beta <- setNames(as.numeric(did$beta), did$var)
  did_vcov <- as.matrix(did[, grep("^cov[0-9]+$", names(did), value = TRUE), with = FALSE])
  storage.mode(did_vcov) <- "double"
  rownames(did_vcov) <- colnames(did_vcov) <- did$var
  needed <- c(
    "1.downup_ac_pop", "1.post_#1.treat",
    "1.post_#1.downup_ac_pop", "1.treat#1.downup_ac_pop",
    "1.post_#1.treat#1.downup_ac_pop"
  )
  if (!all(needed %in% names(did_beta))) {
    stop("Required DiD terms absent for FE ", fe_id)
  }
  df <- as.numeric(fread(scalar_path)[reg == "evreg1", df_r][1L])
  weight <- function(terms) {
    out <- setNames(numeric(length(did_beta)), names(did_beta))
    out[terms] <- 1
    out
  }
  w_pre <- weight("1.downup_ac_pop")
  w_control_post <- weight(c("1.downup_ac_pop", "1.post_#1.downup_ac_pop"))
  w_treated_post <- weight(c(
    "1.post_#1.treat", "1.downup_ac_pop", "1.post_#1.downup_ac_pop",
    "1.treat#1.downup_ac_pop", "1.post_#1.treat#1.downup_ac_pop"
  ))
  w_difference <- w_treated_post - w_control_post
  weights <- list(w_pre, w_control_post, w_treated_post, w_difference)
  results95 <- rbindlist(lapply(weights, function(w) {
    as.list(linear_result(did_beta, did_vcov, w, df, 0.95))
  }))
  results90 <- rbindlist(lapply(weights, function(w) {
    as.list(linear_result(did_beta, did_vcov, w, df, 0.90))
  }))
  results95[, `:=`(
    lower90 = results90$lower,
    upper90 = results90$upper,
    group = c("Pre", "Control post", "Treated post", "Difference"),
    x = c(0.9, 3.25, 3.25, 4.68)
  )]
  diff_t <- results95[group == "Difference", estimate / se]
  p_value <- 2 * pt(-abs(diff_t), df = df)
  p_label <- if (p_value < 0.01) "p-value\n< 0.01" else if (p_value < 0.05) {
    "p-value\n< 0.05"
  } else if (p_value < 0.1) "p-value\n< 0.10" else "p-value\n> 0.10"

  pre_y <- results95[group == "Pre", estimate]
  control_y <- results95[group == "Control post", estimate]
  treated_y <- results95[group == "Treated post", estimate]
  midpoint <- mean(c(control_y, treated_y))
  control_label_y <- control_y
  treated_label_y <- treated_y
  if (abs(treated_y - control_y) < 7.5) {
    direction <- if (treated_y >= control_y) 1 else -1
    treated_label_y <- midpoint + direction * 3.75
    control_label_y <- midpoint - direction * 3.75
  }
  points <- results95[group != "Difference"]
  plot <- ggplot() +
    geom_hline(yintercept = 0, colour = "grey25") +
    geom_segment(
      aes(x = 0.95, y = pre_y, xend = 3.08, yend = control_y),
      arrow = grid::arrow(length = grid::unit(0.10, "inches")), linewidth = 0.4
    ) +
    geom_segment(
      aes(x = 0.95, y = pre_y, xend = 3.08, yend = treated_y),
      arrow = grid::arrow(length = grid::unit(0.10, "inches")), linewidth = 0.4
    ) +
    geom_errorbar(
      data = points, aes(x = x, ymin = lower, ymax = upper),
      width = 0.025, linewidth = 0.45
    ) +
    geom_errorbar(
      data = points, aes(x = x, ymin = lower90, ymax = upper90),
      width = 0.055, linewidth = 1.05
    ) +
    geom_point(data = points, aes(x = x, y = estimate), shape = 21, size = 3.3, fill = "black") +
    annotate("text", x = 0.73, y = pre_y, label = "Non-Agricultural\nPolitician", hjust = 1, size = 3.4) +
    annotate("text", x = 3.42, y = control_label_y, label = "Non-Agricultural\nPolitician", hjust = 0, size = 3.4) +
    annotate("text", x = 3.42, y = treated_label_y, label = "Agricultural\nPolitician", hjust = 0, size = 3.4) +
    annotate("text", x = 0.9, y = -22, label = "Pre", size = 3.5) +
    annotate("text", x = 3.25, y = -22, label = "Post", size = 3.5) +
    annotate("segment", x = 4.55, xend = 4.68, y = control_y, yend = control_y) +
    annotate("segment", x = 4.55, xend = 4.68, y = treated_y, yend = treated_y) +
    annotate("segment", x = 4.68, xend = 4.68, y = control_y, yend = treated_y) +
    annotate("segment", x = 4.68, xend = 4.72, y = midpoint, yend = midpoint) +
    annotate("text", x = 4.78, y = midpoint, label = p_label, hjust = 0, size = 3.1) +
    coord_cartesian(xlim = c(-0.35, 5.5), ylim = c(-26, 40), clip = "off") +
    labs(x = NULL, y = "Effect of Down>Up on Number of Fires (x 1,000)") +
    theme_classic(base_size = 12) +
    theme(
      axis.line.x = element_blank(), axis.text.x = element_blank(),
      axis.ticks.x = element_blank(), plot.margin = margin(8, 35, 8, 8)
    )
  output <- file.path(
    figure_dir,
    paste0("politician_byprov_fe", tag, "_did_interaction_rural_acpop_all_1.png")
  )
  ggsave(output, plot, width = 7.2, height = 4.4, dpi = 300)
  message("Generated: ", output)
}

coefficients <- rbindlist(coefficient_rows)
setorder(coefficients, fe_id, version, time)
averages <- rbindlist(average_rows)
setorder(averages, fe_id, version, period)
fwrite(
  coefficients,
  file.path(table_dir, "politician_byprov_fe_sweep_coefficients.csv")
)
fwrite(
  averages,
  file.path(table_dir, "politician_byprov_fe_sweep_pre_post_averages.csv")
)
message("Prepared all 32 FE report inputs.")
