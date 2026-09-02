#!/usr/bin/env Rscript

# Plot the exploratory October-November balance event study. This script is
# intentionally separate from the production event-study plot registry.

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
repo <- "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
sample <- ""
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--root" && i < length(args)) {
    repo <- args[[i + 1L]]
    i <- i + 2L
  } else if (args[[i]] == "--sample") {
    has_value <- i < length(args) && !startsWith(args[[i + 1L]], "--")
    sample <- if (has_value) args[[i + 1L]] else ""
    if (sample == "none") sample <- ""
    i <- i + if (has_value) 2L else 1L
  } else {
    stop("Unknown or incomplete argument: ", args[[i]])
  }
}

repo <- normalizePath(repo, winslash = "/", mustWork = FALSE)
result_dir <- file.path(
  repo, "tables", "exploratory_analysis", "fire_season_timing"
)
figure_dir <- file.path(
  repo, "figures", "exploratory_analysis", "fire_season_timing"
)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
input <- file.path(
  result_dir, paste0("fire_season_start_event_study", sample, "_rural.csv")
)
if (!file.exists(input)) stop("Missing exploratory result: ", input)

saved <- fread(input)
model <- saved[reg == "evreg1"]
row_indices <- grep("relative_year_bin_aux#1[.]treat$", model$var)
if (length(row_indices) != 11L) {
  stop("Expected 11 estimated event-time interactions; found ", length(row_indices))
}
covariance_columns <- paste0("cov", row_indices)
if (!all(covariance_columns %in% names(model))) {
  stop("Saved covariance columns do not match the event coefficients")
}

event <- data.table(
  relative_month = as.integer(sub("[^0-9].*$", "", model$var[row_indices])) - 6L,
  estimate = 100 * model$beta[row_indices]
)
vcov <- 10000 * as.matrix(model[row_indices, ..covariance_columns])
event[, se := sqrt(diag(vcov))]
event[, `:=`(
  lower = estimate - 1.96 * se,
  upper = estimate + 1.96 * se
)]
event <- rbind(
  event,
  data.table(relative_month = 0L, estimate = 0, se = 0, lower = 0, upper = 0)
)
setorder(event, relative_month)

plot <- ggplot(event, aes(relative_month, estimate)) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#279FF5", alpha = 0.2) +
  geom_line(colour = "#279FF5", linewidth = 0.8) +
  geom_point(shape = 15, size = 2.2, colour = "#279FF5") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "blue") +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
  scale_x_continuous(breaks = -5:6) +
  labs(
    x = "Months from Downwind-Treatment Switch",
    y = "Difference in October-November Window (percentage points)"
  ) +
  theme_classic(base_size = 12) +
  theme(
    panel.grid.major = element_line(colour = "grey85", linetype = "dashed"),
    panel.grid.minor = element_blank()
  )

output <- file.path(
  figure_dir,
  paste0("fire_season_start_event_study", sample, "_rural.png")
)
ggsave(output, plot, width = 8, height = 4, dpi = 300)
message("Generated: ", output)
