#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(ggplot2))

repo <- normalizePath(
  Sys.getenv(
    "REPLICATION_REPO",
    unset = "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
  ),
  winslash = "/", mustWork = TRUE
)

# RA benchmark: _app_21_5km_allfe_same_term.log, FE3.
# Attempt: protest_event_fe03_1378410.stata.log. Both use the same 67,728,314
# observations and 12,096 clusters.
event_time <- c(-4, -3, -2, 0, 1, 2, 3, 4)
audit <- rbind(
  data.frame(
    event_time = event_time,
    estimate = c(
      -42.01641, -8.181174, -20.40768, 56.44675,
      164.7035, 64.44406, 69.70303, 82.60937
    ),
    se = c(
      13.70218, 10.15766, 10.99382, 10.52979,
      28.49049, 12.78092, 13.62757, 19.89362
    ),
    specification = "RA literal RHS"
  ),
  data.frame(
    event_time = event_time,
    estimate = c(
      -41.63327, -7.795929, -20.25265, 56.00096,
      164.2201, 64.15177, 69.38762, 82.22586
    ),
    se = c(
      13.76350, 10.19059, 10.97072, 10.50103,
      28.52140, 12.77580, 13.62263, 19.89927
    ),
    specification = "Constant-moderator attempt"
  )
)
audit$lower <- audit$estimate - 1.96 * audit$se
audit$upper <- audit$estimate + 1.96 * audit$se

omitted <- data.frame(
  event_time = -1,
  estimate = 0,
  se = 0,
  lower = 0,
  upper = 0,
  specification = unique(audit$specification)
)
plot_data <- rbind(audit, omitted)
plot_data <- plot_data[order(plot_data$specification, plot_data$event_time), ]

p <- ggplot(
  plot_data,
  aes(event_time, estimate, colour = specification, fill = specification)
) +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.85) +
  geom_point(size = 2.1) +
  geom_vline(xintercept = -1, linetype = "dashed", colour = "blue") +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "purple") +
  scale_x_continuous(breaks = -4:4) +
  labs(
    x = "Time from Treatment (years)",
    y = "Effect on Number of Fires (in 1,000 units)",
    colour = NULL,
    fill = NULL
  ) +
  theme_classic(base_size = 12) +
  theme(
    panel.grid.major = element_line(colour = "grey85", linetype = "dashed"),
    panel.grid.minor = element_blank(),
    legend.position = "top"
  )

output_dir <- file.path(repo, "figures", "exploratory_analysis")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output <- file.path(output_dir, "protest_ra_fe03_replication_audit.png")
ggsave(output, p, width = 8, height = 4, dpi = 300)
message("Generated: ", output)
