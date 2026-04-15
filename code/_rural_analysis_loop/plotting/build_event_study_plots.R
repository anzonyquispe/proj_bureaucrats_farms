################################################################################
# build_event_study_plots.R
# Wrap plotting_event_studies.R tools to loop over every FE spec stored in a
# given CSV and produce an original + rotated event-study PNG per spec.
#
# Row/column positions are detected from the CSV contents (not hard-coded),
# so the script adapts automatically to different event-window sizes (e.g.
# the _sample datasets have fewer bins than the full data).
#
# Required env vars (set by orchestrator):
#   PLOT_DIR     : absolute path to this plotting/ folder
#   FIG_DIR      : where PNGs are written
#   CSV_APP16    : path to the _app_16 polischar event-study CSV
#   CSV_APP17    : path to the _app_17 protest event-study CSV
#   FE_LABELS    : space-separated FE indices run (e.g. "1 8 16 24 32");
#                  evreg1..evregN in the CSV correspond to these FE indices in order
################################################################################

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(ggplot2)
  library(doParallel)
  library(HonestDiD)
})

plot_dir     <- Sys.getenv("PLOT_DIR")
figure_farms <- Sys.getenv("FIG_DIR")
csv_app16    <- Sys.getenv("CSV_APP16")
csv_app17    <- Sys.getenv("CSV_APP17")
fe_labels    <- strsplit(trimws(Sys.getenv("FE_LABELS", "1 8 16 24 32")), "\\s+")[[1]]

stopifnot(nchar(plot_dir) > 0, nchar(figure_farms) > 0,
          nchar(csv_app16) > 0, nchar(csv_app17) > 0)
dir.create(figure_farms, recursive = TRUE, showWarnings = FALSE)

# agregation_result() and plot_honest_from_rds() look up `figure_farms` and
# `file_base` by lexical scoping — keep them as globals.
figure_farms <<- figure_farms

source(file.path(plot_dir, "tools", "plot_event_studies.R"))

################################################################################
# Helpers
################################################################################

# Given a `var` column for a single evreg, return the row indices of the
# event-time-by-treat interaction terms. Under tight FE specs the main-effect
# rows may be dropped (Stata suffixes them with "o"/"bno"), but the
# interactions always carry the full aux range. Accept both live and "o"-marked
# variants so the detector is robust to collinearity.
find_interaction_rows <- function(var_vec) {
  grep("relative_year_bin_aux#1o?\\.treat$", var_vec)
}

# Parse "2.relative_year_bin_aux" / "1bn.relative_year_bin_aux..." /
# "2o.relative_year_bin_aux" / "1bno.relative_year_bin_aux..." -> integer 2 / 1.
parse_aux_level <- function(x) {
  as.integer(sub("^([0-9]+)(bno?|o)?\\..*$", "\\1", x))
}

# Discover the omitted aux level from the full aux range and what appears.
find_omitted_level <- function(present_levels) {
  rng <- seq(min(present_levels), max(present_levels))
  miss <- setdiff(rng, present_levels)
  if (length(miss) != 1) {
    stop("Expected exactly one omitted event-time level, got: ",
         paste(miss, collapse = ","))
  }
  miss
}

run_one <- function(df, filterval, file_base_local,
                    xlab, ylab) {

  sub <- df[reg == filterval]
  if (nrow(sub) == 0) {
    message("  skip ", filterval, " (no rows)")
    return(invisible(NULL))
  }

  # 1) Find interaction-row indices and the aux level of each.
  int_rows <- find_interaction_rows(sub$var)
  if (length(int_rows) < 3) {
    message("  skip ", filterval, " (only ", length(int_rows), " interaction rows)")
    return(invisible(NULL))
  }
  int_aux <- parse_aux_level(sub$var[int_rows])

  # 2) Omitted aux level is the gap in the interaction-row sequence. The
  #    regression sets the same base for main and interaction terms, and the
  #    interactions are always written out (main effects may be collinear with
  #    FEs and get dropped under tight specs).
  omitted_aux <- find_omitted_level(int_aux)

  # 3) Event-window counts, assuming omitted event time == -1 (the convention
  #    our regressions enforce via `base = -1 - rmin + 1`).
  numPrePeriods  <- sum(int_aux < omitted_aux) + 1   # include the omitted period
  numPostPeriods <- sum(int_aux > omitted_aux)

  # agregation_result with omitted_period=-1 expects numPrePeriods + numPostPeriods - 1
  # rows in ev (the omitted period is added back inside). Since int_rows already
  # excludes the omitted aux, that identity holds: length(int_rows) ==
  # (numPrePeriods - 1) + numPostPeriods.

  # 4) Slice: beta, ymean, and the variance submatrix for the interaction rows.
  cov_cols <- paste0("cov", int_rows)
  missing_cols <- setdiff(cov_cols, names(sub))
  if (length(missing_cols) > 0) {
    message("  skip ", filterval, " (missing cov cols: ",
            paste(missing_cols, collapse = ","), ")")
    return(invisible(NULL))
  }
  ev <- sub[int_rows, c("beta", "ymean", cov_cols), with = FALSE]

  file_base <<- file_base_local

  agregation_result(
    ev,
    numPrePeriods  = numPrePeriods,
    numPostPeriods = numPostPeriods,
    M              = 1,
    xlab           = xlab,
    ylab           = ylab,
    omitted_period = -1,
    honest         = FALSE
  )
  message("  wrote ", file_base_local, "_{ori,rotated}.png  (pre=",
          numPrePeriods, " post=", numPostPeriods, ")")
}

################################################################################
# _app_16 — politician characteristics event study
################################################################################

message("Event studies — politician characteristics (_app_16)")
df16 <- fread(csv_app16)

for (k in seq_along(fe_labels)) {
  fe_idx <- fe_labels[k]
  run_one(
    df              = df16,
    filterval       = paste0("evreg", k),
    file_base_local = paste0("app16_polischar_evst_fe", fe_idx),
    xlab            = "Time from Treatment (years)",
    ylab            = "Effect on Number of Fires (in 1,000 units)"
  )
}

################################################################################
# _app_17 — protest event study
################################################################################

message("\nEvent studies — protest (_app_17)")
df17 <- fread(csv_app17)

for (k in seq_along(fe_labels)) {
  fe_idx <- fe_labels[k]
  run_one(
    df              = df17,
    filterval       = paste0("evreg", k),
    file_base_local = paste0("app17_protest_evst_fe", fe_idx),
    xlab            = "Time from Protest (months)",
    ylab            = "Effect on Number of Fires (in 1,000 units)"
  )
}

message("\nEvent study plots complete.")
