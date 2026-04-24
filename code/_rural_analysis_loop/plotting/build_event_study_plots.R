################################################################################
# build_full_event_study_plots.R
# Full-variant event-study plot builder. For every (app, variant, set) combo,
# read its ster->csv output and emit one `_ori.png` + one `_rotated.png` per
# FE spec in the set. Output filenames encode the actual FE number AND the
# rural-variant tag so the downstream LaTeX can index plots by fe + variant.
#
# Required env vars (set by run_full_report.sh):
#   PLOT_DIR : path to plotting/ folder
#   FIG_DIR  : output directory for PNGs
#   CSV_DIR  : directory holding ster->csv outputs
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
csv_dir      <- Sys.getenv("CSV_DIR")

stopifnot(nchar(plot_dir) > 0, nchar(figure_farms) > 0, nchar(csv_dir) > 0)
dir.create(figure_farms, recursive = TRUE, showWarnings = FALSE)

figure_farms <<- figure_farms
source(file.path(plot_dir, "tools", "plot_event_studies.R"))

################################################################################
# Helpers (same detection logic as build_event_study_plots.R)
################################################################################

find_interaction_rows <- function(var_vec) {
  grep("relative_year_bin_aux#1o?\\.treat$", var_vec)
}

parse_aux_level <- function(x) {
  as.integer(sub("^([0-9]+)(bno?|o)?\\..*$", "\\1", x))
}

find_omitted_level <- function(present_levels) {
  rng <- seq(min(present_levels), max(present_levels))
  miss <- setdiff(rng, present_levels)
  if (length(miss) != 1) {
    stop("Expected exactly one omitted event-time level, got: ",
         paste(miss, collapse = ","))
  }
  miss
}

run_one <- function(df, filterval, file_base_local, xlab, ylab) {

  sub <- df[reg == filterval]
  if (nrow(sub) == 0) {
    message("  skip ", filterval, " (no rows)")
    return(invisible(NULL))
  }

  int_rows <- find_interaction_rows(sub$var)
  if (length(int_rows) < 3) {
    message("  skip ", filterval, " (only ", length(int_rows), " interaction rows)")
    return(invisible(NULL))
  }
  int_aux     <- parse_aux_level(sub$var[int_rows])
  omitted_aux <- find_omitted_level(int_aux)

  numPrePeriods  <- sum(int_aux < omitted_aux) + 1
  numPostPeriods <- sum(int_aux > omitted_aux)

  cov_cols     <- paste0("cov", int_rows)
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
# FE set mapping -- MUST match sbatch_cluster/_generate_sbatch_files.sh
################################################################################

variants <- c("area", "farzad")

app16_sets <- list(
  set1 = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 23, 25),
  set2 = c(15, 16, 17, 18, 19, 20, 21, 22, 24, 26, 27, 28, 30, 31, 29, 32)
)

app17_sets <- list(
  set1 = c(1, 2, 3, 4, 5, 6, 7, 23),
  set2 = c(8, 9, 10, 11, 12, 13, 14, 25),
  set3 = c(15, 16, 17, 18, 19, 20, 21, 29),
  set4 = c(22, 24, 26, 27, 28, 30, 31, 32)
)

app16_csv_tpl <- file.path(csv_dir, "_app_16_polischar_evst_all_rural_%s_%s.csv")
app17_csv_tpl <- file.path(csv_dir, "_app_17_5km_evst_all_rural_%s_%s.csv")

################################################################################
# _app_16 politician event study
################################################################################

message("Event studies -- politician characteristics (_app_16)")
for (v in variants) {
  for (s in names(app16_sets)) {
    csv <- sprintf(app16_csv_tpl, v, s)
    if (!file.exists(csv)) { message("  missing CSV: ", csv); next }
    df        <- fread(csv)
    fe_labels <- app16_sets[[s]]
    message("  ", s, " / ", v, "  (", length(fe_labels), " specs)")
    for (k in seq_along(fe_labels)) {
      fe <- fe_labels[k]
      run_one(
        df              = df,
        filterval       = paste0("evreg", k),
        file_base_local = sprintf("app16_polischar_evst_fe%d_%s", fe, v),
        xlab            = "Time from Treatment (years)",
        ylab            = "Effect on Number of Fires (in 1,000 units)"
      )
    }
  }
}

################################################################################
# _app_17 protest event study
################################################################################

message("\nEvent studies -- protest (_app_17)")
for (v in variants) {
  for (s in names(app17_sets)) {
    csv <- sprintf(app17_csv_tpl, v, s)
    if (!file.exists(csv)) { message("  missing CSV: ", csv); next }
    df        <- fread(csv)
    fe_labels <- app17_sets[[s]]
    message("  ", s, " / ", v, "  (", length(fe_labels), " specs)")
    for (k in seq_along(fe_labels)) {
      fe <- fe_labels[k]
      run_one(
        df              = df,
        filterval       = paste0("evreg", k),
        file_base_local = sprintf("app17_protest_evst_fe%d_%s", fe, v),
        xlab            = "Time from Protest (months)",
        ylab            = "Effect on Number of Fires (in 1,000 units)"
      )
    }
  }
}

message("\nFull event-study plots complete.")
