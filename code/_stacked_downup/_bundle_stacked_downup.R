#!/usr/bin/env Rscript
###############################################################################
# _bundle_stacked_downup.R
#
# Aggregates the per-cohort CSV files produced by _build_stacked_downup.R
# into a single combined Stata dataset, written to:
#
#   <root>/data_output/intermediate/combined_dt.dta
#
# Toggles (env vars; defaults match the build script):
#   LOCATION    "shell" | "dbox"    data root selector
#   SAMPLE      ""      | "_sample" suffix on input/output filenames
#   SHELL_ROOT  override for $shell
#   DBOX_ROOT   override for $dbox
###############################################################################

suppressPackageStartupMessages({
  library(data.table)
  library(haven)
})

# ---- Toggles / paths --------------------------------------------------------
location   <- Sys.getenv("LOCATION", "dbox")
sample_tag <- Sys.getenv("SAMPLE",   "")

shell_root <- Sys.getenv("SHELL_ROOT",
  "/groups/sgulzar/sa_fires/proj_bureaucrats_farms")
dbox_root  <- Sys.getenv("DBOX_ROOT",
  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms")
root <- if (location == "shell") shell_root else dbox_root

intermediate_dir <- file.path(root, "data_output", "intermediate")
source_dir       <- file.path(intermediate_dir,
                              paste0("stacked_downup", sample_tag))

if (!dir.exists(source_dir)) {
  stop("Source directory does not exist: ", source_dir)
}

csv_files <- list.files(source_dir, pattern = "^cohort_.*\\.csv$",
                        full.names = TRUE)
if (length(csv_files) == 0L) {
  stop("No cohort_*.csv files found in ", source_dir)
}

message("Source dir:       ", source_dir)
message("Cohort files:     ", length(csv_files))

# ---- Combine ----------------------------------------------------------------
message("Reading and combining cohort files...")
combined_dt <- rbindlist(lapply(csv_files, fread), fill = TRUE)
message("Combined rows:    ", nrow(combined_dt))
message("Combined columns: ", paste(names(combined_dt), collapse = ", "))

# ---- Write output -----------------------------------------------------------
out_path <- file.path(intermediate_dir, paste0("combined_dt", sample_tag, ".dta"))
write_dta(combined_dt, out_path)
message("Wrote: ", out_path)

message("\nDone.")
