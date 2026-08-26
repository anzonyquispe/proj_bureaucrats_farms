#!/usr/bin/env Rscript

# AC-level treatment-status panel, September 2012--August 2022.
# Units are sorted by first treatment timing; never-treated ACs appear last.

suppressPackageStartupMessages({
  library(haven)
  library(panelView)
})

repo <- "C:/Users/eunic/OneDrive/Documents/GitHub/proj_bureaucrats_farms"
data_root <- "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms"
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1L && nzchar(args[[1L]])) data_root <- args[[1L]]
if (length(args) >= 2L && nzchar(args[[2L]])) repo <- args[[2L]]

input <- file.path(
  data_root, "data_output", "intermediate", "panel_data_election_year.dta"
)
output <- file.path(repo, "figures", "panelview_self_profession.png")
if (!file.exists(input)) stop("Missing input: ", input)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)

panel <- read_dta(
  input,
  col_select = c(ac_uq_id, year, month, self_profession)
)
panel <- as.data.frame(panel)
panel <- panel[
  (panel$year > 2012 | (panel$year == 2012 & panel$month >= 9)) &
  (panel$year < 2022 | (panel$year == 2022 & panel$month <= 8)),
]
panel$month_index <- (panel$year - 2012L) * 12L + panel$month - 8L
panel$self_profession <- as.integer(panel$self_profession)
panel$self_profession[is.na(panel$self_profession)] <- 0L

if (anyDuplicated(panel[c("ac_uq_id", "month_index")])) {
  stop("Election panel is not unique by ac_uq_id and month_index")
}
if (!setequal(unique(panel$month_index), 1:120) ||
    length(unique(panel$month_index)) != 120L) {
  stop("Expected complete calendar support from month 1 through month 120")
}
if (!all(panel$self_profession %in% 0:1)) {
  stop("self_profession must contain only 0, 1, or missing values")
}

# panelView performs the treatment-timing sort. Capture its ggplot first so we
# can request the exact month labels 1, 12, 24, ..., 120.
pdf(NULL)
plot <- panelview(
  data = panel,
  D = "self_profession",
  index = c("ac_uq_id", "month_index"),
  type = "treat",
  by.timing = TRUE,
  display.all = TRUE,
  axis.lab = "time",
  axis.lab.gap = c(0, 0),
  axis.lab.angle = 0,
  xlab = "Month (1 = September 2012; 120 = August 2022)",
  ylab = "",
  main = "",
  legend.labs = c("Non-agricultural profession", "Agricultural profession"),
  color = c("#cfe2f3", "#1f77b4"),
  gridOff = TRUE,
  cex.axis.x = 10,
  cex.legend = 11
)
dev.off()

month_breaks <- c(1L, seq.int(12L, 120L, by = 12L))
plot <- plot + ggplot2::scale_x_continuous(
  expand = c(0, 0), breaks = month_breaks, labels = month_breaks
)

png(output, width = 2600, height = 1800, res = 220)
print(plot)
dev.off()

message("Generated: ", output)
