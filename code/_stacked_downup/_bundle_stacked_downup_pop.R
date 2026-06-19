#!/usr/bin/env Rscript
###############################################################################
# _bundle_stacked_downup_pop.R
#
# Aggregates the per-cohort .dta files produced by _build_stacked_downup_pop.R
# into a single combined Stata dataset, written to BOTH:
#
#   1. DOWNLOADS_DIR/combined_dt_pop.dta
#      (user-facing copy in Downloads, for ad-hoc exploration)
#
#   2. <root>/data_output/intermediate/combined_dt_pop.dta
#      (canonical copy that the analysis dofiles read)
#
# Toggles (env vars; defaults match the build script):
#   LOCATION       "shell" | "dbox"     data root selector
#   SAMPLE         ""      | "_sample"  suffix on input/output filenames
#   SHELL_ROOT     override for $shell
#   DBOX_ROOT      override for $dbox
#   DOWNLOADS_DIR  per-cohort/combined output dir (default Mac Downloads path)
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

downloads_dir <- Sys.getenv("DOWNLOADS_DIR",
  "/Users/anzony.quisperojas/Downloads/stackedata")

intermediate_dir <- file.path(root, "data_output", "intermediate")

# Match the build script's primary/fallback logic so we read from wherever
# the build wrote.
primary_source_dir  <- file.path(downloads_dir,
                                paste0("stacked_downup_pop", sample_tag))
fallback_source_dir <- file.path(intermediate_dir,
                                paste0("stacked_downup_pop", sample_tag))

source_dir <- if (dir.exists(primary_source_dir)) {
  primary_source_dir
} else if (dir.exists(fallback_source_dir)) {
  fallback_source_dir
} else {
  stop("No per-cohort source directory found. Tried:\n  ",
       primary_source_dir, "\n  ", fallback_source_dir)
}

dta_files <- list.files(source_dir, pattern = "^cohort_.*\\.dta$",
                        full.names = TRUE)
if (length(dta_files) == 0L) {
  stop("No cohort_*.dta files found in ", source_dir)
}

message("Source dir:       ", source_dir)
message("Cohort files:     ", length(dta_files))

# ---- Combine ----------------------------------------------------------------
message("Reading and combining cohort files...")
combined_dt <- rbindlist(lapply(dta_files, function(f) as.data.table(read_dta(f))),
                        fill = TRUE)
message("Combined rows:    ", nrow(combined_dt))
message("Combined columns: ", paste(names(combined_dt), collapse = ", "))

# ---- Write outputs ---------------------------------------------------------
intermediate_out <- file.path(intermediate_dir, "combined_dt_pop.dta")
write_dta(combined_dt, intermediate_out)
message("Wrote: ", intermediate_out)

# Also drop a copy in the Downloads dir for easy ad-hoc access.
downloads_out <- file.path(downloads_dir, "combined_dt_pop.dta")
ok <- tryCatch({
  dir.create(downloads_dir, showWarnings = FALSE, recursive = TRUE)
  write_dta(combined_dt, downloads_out)
  TRUE
}, error = function(e) {
  message("Could not write Downloads copy (", downloads_out, "): ",
          conditionMessage(e))
  FALSE
})
if (ok) message("Wrote: ", downloads_out)

message("\nDone.")
