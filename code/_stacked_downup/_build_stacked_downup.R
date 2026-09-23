#!/usr/bin/env Rscript
###############################################################################
# _build_stacked_downup.R
#
# Builds a stacked DiD dataset around downup_ac 0->1 switching events,
# at the unique_small_grid_id x monthyear level. Mirrors the logic that
# precedes the DiD in _main_1_did.do, but constructs a stacked panel.
#
# Memory model
# ------------
#   * Only the columns needed downstream are read from the master CSV.
#   * Each cohort's stack is written to its own CSV in a per-run folder
#     and dropped from memory immediately -- nothing is accumulated.
#   * Cohorts are processed in parallel via parallel::mclapply across
#     CORES forked workers (default 10).  The parent dt is shared by the
#     OS's copy-on-write fork semantics, so 10 workers do not multiply
#     the resident set by 10 as long as they don't mutate dt.  The
#     cohort builder only does read-only filtering on dt -- never `:=`.
#
# Algorithm  (per cohort c)
# -------------------------
#   1. Treated grids = grids with a 0 -> 1 transition in downup_ac at c.
#   2. Cohort window [t_min, t_max], pooled across treated grids:
#        t_min = min(monthyear) when downup_ac == 0
#        t_max = max(monthyear) when downup_ac == 1
#   3. Treated rows: contiguous "clean" stretch around c per grid
#        d_pre  = latest monthyear < c with downup_ac == 1   (or -Inf)
#        d_post = earliest monthyear > c with downup_ac == 0 (or +Inf)
#      intersected with [t_min, t_max].
#   4. Control rows: any grid not treated at c whose downup_ac is 0 in a
#      contiguous stretch covering c:
#        d_pre  = latest monthyear < c with downup_ac == 1   (or -Inf)
#        d_post = earliest monthyear > c with downup_ac == 1 (or +Inf)
#      intersected with [t_min, t_max].
#
# Per-cohort output:
#   <root>/data_output/intermediate/stacked_downup<sample>/cohort_<c>.csv
# with columns:
#   unique_small_grid_id, month, year, monthyear, province, ac_uq_id,
#   downup_ac, count, av_wind_speed, wind_direction, rice_prod_aclvl_ahigh,
#   treat, cohort, relative_monthyear
#
# Toggles (env vars; defaults match _main_1_did.do):
#   LOCATION    "shell" | "dbox"    data root selector
#   SAMPLE      ""      | "_sample" suffix on input/output filenames
#   CORES       integer (default 10)
#   SHELL_ROOT  override for $shell
#   DBOX_ROOT   override for $dbox
###############################################################################

suppressPackageStartupMessages({
  library(data.table)
  library(parallel)
})

# ---- Toggles / paths --------------------------------------------------------
location   <- Sys.getenv("LOCATION", "dbox")
sample_tag <- Sys.getenv("SAMPLE",   "")
cores      <- as.integer(Sys.getenv("CORES", "10"))
if (is.na(cores) || cores < 1L) cores <- 1L

shell_root <- Sys.getenv("SHELL_ROOT",
  "/groups/sgulzar/sa_fires/proj_bureaucrats_farms")
dbox_root  <- Sys.getenv("DBOX_ROOT",
  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms")
root <- if (location == "shell") shell_root else dbox_root

input_path  <- file.path(root, "data_output", "intermediate",
                         paste0("0_master_merge_data_gen", sample_tag, ".csv"))
output_dir  <- file.path(root, "data_output", "intermediate",
                         paste0("stacked_downup", sample_tag))

stopifnot(file.exists(input_path))
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Keep data.table from spawning its own threads inside each fork -- one
# thread per worker keeps total threads ~= CORES instead of CORES * nproc.
setDTthreads(1L)

# ---- Load -------------------------------------------------------------------
keep_cols <- c("unique_small_grid_id", "month", "year", "monthyear",
               "province", "ac_uq_id", "downup_ac", "count",
               "av_wind_speed", "wind_direction", "rice_prod_aclvl_ahigh")

message("Reading: ", input_path)
dt <- fread(input_path, select = keep_cols)

missing <- setdiff(keep_cols, names(dt))
if (length(missing) > 0L) {
  stop("Input is missing required columns: ", paste(missing, collapse = ", "))
}

dt[, downup_ac := as.integer(downup_ac)]
setorder(dt, unique_small_grid_id, monthyear)

# ---- Detect 0 -> 1 switching events ----------------------------------------
dt[, downup_lag := shift(downup_ac, 1L, type = "lag"),
   by = unique_small_grid_id]
dt[, is_switch  := !is.na(downup_lag) & downup_lag == 0L & downup_ac == 1L]

cohorts   <- sort(unique(dt[is_switch == TRUE, monthyear]))
all_grids <- unique(dt$unique_small_grid_id)

message("Total rows in input:  ", nrow(dt))
message("Unique grids:         ", length(all_grids))
message("Number of cohorts:    ", length(cohorts))
message("Output directory:     ", output_dir)
message("Workers (CORES):      ", cores)

# ---- Build + write one cohort ----------------------------------------------
process_cohort <- function(c_value) {

  out_file <- file.path(output_dir, sprintf("cohort_%s.csv", as.character(c_value)))

  # 1. Treated grids for this cohort
  treated_grids <- unique(dt[is_switch == TRUE & monthyear == c_value,
                              unique_small_grid_id])
  if (length(treated_grids) == 0L) return(list(cohort = c_value, rows = 0L, file = NA_character_))

  # 2. Cohort window pooled across treated grids
  t_min <- dt[unique_small_grid_id %in% treated_grids & downup_ac == 0L,
              min(monthyear, na.rm = TRUE)]
  t_max <- dt[unique_small_grid_id %in% treated_grids & downup_ac == 1L,
              max(monthyear, na.rm = TRUE)]
  if (!is.finite(t_min) || !is.finite(t_max)) {
    return(list(cohort = c_value, rows = 0L, file = NA_character_))
  }

  # 3. Treated rows -- contiguous clean window around c, per grid
  treated_pre  <- dt[unique_small_grid_id %in% treated_grids &
                     monthyear < c_value & downup_ac == 1L,
                     .(d_pre = max(monthyear)),
                     by = unique_small_grid_id]
  treated_post <- dt[unique_small_grid_id %in% treated_grids &
                     monthyear > c_value & downup_ac == 0L,
                     .(d_post = min(monthyear)),
                     by = unique_small_grid_id]
  treated_bounds <- data.table(unique_small_grid_id = treated_grids)
  treated_bounds <- merge(treated_bounds, treated_pre,
                          by = "unique_small_grid_id", all.x = TRUE)
  treated_bounds <- merge(treated_bounds, treated_post,
                          by = "unique_small_grid_id", all.x = TRUE)
  treated_bounds[is.na(d_pre),  d_pre  := -Inf]
  treated_bounds[is.na(d_post), d_post :=  Inf]

  treated_data <- dt[unique_small_grid_id %in% treated_grids &
                     monthyear >= t_min & monthyear <= t_max]
  treated_data <- merge(treated_data, treated_bounds,
                        by = "unique_small_grid_id")
  treated_data <- treated_data[monthyear > d_pre & monthyear < d_post]
  treated_data[, c("d_pre", "d_post") := NULL]
  treated_data[, treat := 1L]

  # 4. Control candidates -- any other grid that is not treated at c
  ctrl_candidates <- setdiff(all_grids, treated_grids)
  treated_at_c <- dt[unique_small_grid_id %in% ctrl_candidates &
                     monthyear == c_value & downup_ac == 1L,
                     unique(unique_small_grid_id)]
  ctrl_candidates <- setdiff(ctrl_candidates, treated_at_c)

  if (length(ctrl_candidates) == 0L) {
    out <- treated_data
  } else {
    # 5. Control rows
    ctrl_pre  <- dt[unique_small_grid_id %in% ctrl_candidates &
                    monthyear < c_value & downup_ac == 1L,
                    .(d_pre = max(monthyear)),
                    by = unique_small_grid_id]
    ctrl_post <- dt[unique_small_grid_id %in% ctrl_candidates &
                    monthyear > c_value & downup_ac == 1L,
                    .(d_post = min(monthyear)),
                    by = unique_small_grid_id]
    ctrl_bounds <- data.table(unique_small_grid_id = ctrl_candidates)
    ctrl_bounds <- merge(ctrl_bounds, ctrl_pre,
                         by = "unique_small_grid_id", all.x = TRUE)
    ctrl_bounds <- merge(ctrl_bounds, ctrl_post,
                         by = "unique_small_grid_id", all.x = TRUE)
    ctrl_bounds[is.na(d_pre),  d_pre  := -Inf]
    ctrl_bounds[is.na(d_post), d_post :=  Inf]

    ctrl_data <- dt[unique_small_grid_id %in% ctrl_candidates &
                    monthyear >= t_min & monthyear <= t_max &
                    downup_ac == 0L]
    ctrl_data <- merge(ctrl_data, ctrl_bounds,
                       by = "unique_small_grid_id")
    ctrl_data <- ctrl_data[monthyear > d_pre & monthyear < d_post]
    ctrl_data[, c("d_pre", "d_post") := NULL]

    if (nrow(ctrl_data) == 0L) {
      out <- treated_data
    } else {
      ctrl_data[, treat := 0L]
      out <- rbind(treated_data, ctrl_data, fill = TRUE)
    }
  }

  out[, cohort := c_value]
  out[, relative_monthyear := monthyear - c_value]

  # Strip helper columns inherited from dt
  for (col in c("downup_lag", "is_switch")) {
    if (col %in% names(out)) out[, (col) := NULL]
  }

  # Write to disk and release memory
  fwrite(out, out_file)
  n <- nrow(out)
  rm(out, treated_data); gc(verbose = FALSE)

  list(cohort = c_value, rows = n, file = out_file)
}

# ---- Run cohorts (fork-parallel on Unix; sequential on Windows) -------------
# parallel::mclapply relies on fork(), which does not exist on Windows, so there
# `mc.cores > 1` errors out. Fall back to a sequential lapply on Windows (the
# copy-on-write memory sharing that makes forking worthwhile is unavailable
# there anyway).
if (.Platform$OS.type == "windows" || cores == 1L) {
  if (.Platform$OS.type == "windows" && cores > 1L) {
    message("Windows detected: fork-based mclapply is unavailable; running cohorts sequentially.")
  }
  results <- lapply(cohorts, process_cohort)
} else {
  message("Processing cohorts in parallel...")
  results <- mclapply(cohorts, process_cohort,
                      mc.cores = cores,
                      mc.preschedule = FALSE)
}

# Surface any worker errors
errs <- vapply(results, inherits, logical(1L), what = "try-error")
if (any(errs)) {
  failing <- cohorts[errs]
  message("ERRORS in cohorts: ", paste(failing, collapse = ", "))
  for (i in which(errs)) message(conditionMessage(attr(results[[i]], "condition")))
  stop("Aborting due to worker errors.")
}

summary_dt <- rbindlist(results)
total_rows <- sum(summary_dt$rows, na.rm = TRUE)

# Write a small manifest so downstream code can iterate over cohort files.
manifest_path <- file.path(output_dir, "_manifest.csv")
fwrite(summary_dt, manifest_path)

message("\nDone.")
message("  Cohorts written:   ", sum(!is.na(summary_dt$file)))
message("  Total rows across all cohorts: ", total_rows)
message("  Per-cohort files in: ", output_dir)
message("  Manifest: ", manifest_path)
