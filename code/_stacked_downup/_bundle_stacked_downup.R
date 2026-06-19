#!/usr/bin/env Rscript
###############################################################################
# _bundle_stacked_downup.R
#
# Aggregates the per-cohort CSV files produced by _build_stacked_downup.R
# into a single tar.gz archive and drops it next to the source folder, in
#   <root>/data_output/intermediate/stacked_downup<sample>.tar.gz
#
# Toggles (env vars; defaults match the build script):
#   LOCATION    "shell" | "dbox"    data root selector
#   SAMPLE      ""      | "_sample" suffix on input/output filenames
#   SHELL_ROOT  override for $shell
#   DBOX_ROOT   override for $dbox
###############################################################################

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
archive_path     <- file.path(intermediate_dir,
                              paste0("stacked_downup", sample_tag, ".tar.gz"))

if (!dir.exists(source_dir)) {
  stop("Source directory does not exist: ", source_dir)
}

csv_files <- list.files(source_dir, pattern = "\\.csv$", full.names = FALSE)
if (length(csv_files) == 0L) {
  stop("No CSV files found in ", source_dir)
}

message("Source dir:      ", source_dir)
message("Files to bundle: ", length(csv_files))
message("Archive path:    ", archive_path)




setwd(source_dir)
combined_dt <- rbindlist(lapply(csv_files, fread), fill = TRUE)
names(combined_dt)

# Save as CSV first, then compress to tar.gz
fwrite(combined_dt, "combined_dt.csv")
tar("combined_dt.tar.gz", files = "combined_dt.csv", compression = "gzip")

# Clean up the intermediate CSV
file.remove("combined_dt.csv")

library(haven)
setwd(intermediate_dir)
write_dta(combined_dt, "combined_dt.dta")

library(fixest)
mod_twfe = feols(count ~ i(relative_monthyear, treat, ref = -1) + av_wind_speed + wind_direction  |                    ## Other controls
                   unique_small_grid_id^cohort + ac_uq_id^monthyear^cohort, cluster = ~ac_uq_id^monthyear,                          ## Clustered SEs
                 data = combined_dt)

ggiplot()

# ---- Build the archive ------------------------------------------------------
# Use the system `tar` and feed the file list via -T so we don't blow up
# the command line if there are thousands of cohort files. -C makes the
# paths in the archive relative to source_dir (no absolute / Dropbox path
# leaks into the tarball).
list_file <- tempfile(fileext = ".txt")
on.exit(unlink(list_file), add = TRUE)
writeLines(csv_files, list_file)

if (file.exists(archive_path)) file.remove(archive_path)

status <- system2(
  "tar",
  args = c("-czf", shQuote(archive_path),
           "-C",   shQuote(source_dir),
           "-T",   shQuote(list_file))
)

if (status != 0L) {
  stop("tar exited with non-zero status: ", status)
}

# ---- Report -----------------------------------------------------------------
info <- file.info(archive_path)
size_mb <- info$size / (1024 * 1024)

message("\nDone.")
message(sprintf("  Bundled %d files into %s (%.2f MB)",
                length(csv_files), archive_path, size_mb))
