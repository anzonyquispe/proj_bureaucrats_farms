#!/usr/bin/env Rscript

# AC-level treatment-status panel, September 2012--August 2022.
# A reproducible 10% sample of ACs is drawn independently within each province.
# Every monthly observation is then retained for those ACs. Units are sorted by
# first treatment timing; never-treated ACs appear last.

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
sample_output <- file.path(
  repo, "tables", "panelview_self_profession_selected_acs.csv"
)
if (!file.exists(input)) stop("Missing input: ", input)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(sample_output), recursive = TRUE, showWarnings = FALSE)

panel <- read_dta(
  input,
  col_select = c(state, ac_uq_id, year, month, self_profession)
)
panel <- as.data.frame(panel)
panel <- panel[
  (panel$year > 2012 | (panel$year == 2012 & panel$month >= 9)) &
  (panel$year < 2022 | (panel$year == 2022 & panel$month <= 8)),
]
panel$month_index <- (panel$year - 2012L) * 12L + panel$month - 8L
panel$self_profession <- as.integer(panel$self_profession)
panel$self_profession[is.na(panel$self_profession)] <- 0L

# Validate that state is a time-invariant AC attribute before sampling.
state_per_ac <- aggregate(state ~ ac_uq_id, panel, function(x) {
  length(unique(x[!is.na(x)]))
})
if (any(state_per_ac$state != 1L)) {
  stop("Every AC must belong to exactly one province throughout the panel")
}

# Draw approximately 10% of the ACs in every province with a fixed seed. The
# unit of sampling is the AC, never an AC-month row. round() gives 85 selected
# ACs from the current 853-AC panel (24 Bihar, 9 Haryana, 12 Punjab, 40 UP).
sampling_seed <- 20260826L
sampling_fraction <- 0.10
ac_frame <- unique(panel[c("state", "ac_uq_id")])
ac_frame <- ac_frame[order(ac_frame$state, ac_frame$ac_uq_id), ]
set.seed(sampling_seed)
selected_parts <- lapply(split(ac_frame, ac_frame$state), function(frame) {
  number_selected <- max(1L, as.integer(round(nrow(frame) * sampling_fraction)))
  frame[sample.int(nrow(frame), size = number_selected, replace = FALSE), ]
})
selected_acs <- do.call(rbind, selected_parts)
rownames(selected_acs) <- NULL
selected_acs <- selected_acs[order(selected_acs$state, selected_acs$ac_uq_id), ]
selected_acs$sample_seed <- sampling_seed
selected_acs$sample_fraction <- sampling_fraction
write.csv(selected_acs, sample_output, row.names = FALSE, na = "")

panel <- merge(
  panel,
  selected_acs[c("state", "ac_uq_id")],
  by = c("state", "ac_uq_id"),
  all = FALSE,
  sort = FALSE
)

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
months_per_ac <- table(panel$ac_uq_id)
if (any(months_per_ac != 120L)) {
  stop("Every sampled AC must retain all 120 monthly observations")
}
if (nrow(panel) != 120L * nrow(selected_acs)) {
  stop("The plotted panel is not exactly selected ACs x 120 months")
}

sample_counts <- aggregate(
  ac_uq_id ~ state, selected_acs, function(x) length(unique(x))
)
names(sample_counts)[2L] <- "selected_acs"
message("Sampling seed: ", sampling_seed)
message("Selected ACs by province:")
message(paste(capture.output(print(sample_counts, row.names = FALSE)), collapse = "\n"))
message(
  "Retained ", nrow(panel), " AC-month observations for ",
  length(unique(panel$ac_uq_id)), " ACs (120 months per AC)"
)

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
) + ggplot2::theme(
  axis.text.y = ggplot2::element_blank(),
  axis.ticks.y = ggplot2::element_blank()
)

png(output, width = 2600, height = 1800, res = 220)
print(plot)
dev.off()

message("Generated: ", output)
message("Selected-AC audit file: ", sample_output)
