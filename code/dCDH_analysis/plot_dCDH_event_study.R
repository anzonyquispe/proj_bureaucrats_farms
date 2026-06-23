#!/usr/bin/env Rscript
################################################################################
# plot_dCDH_event_study.R
#
# Renders an event-study plot from each dCDH CSV produced by the
# DidMultiplegtDyn pipeline (one .csv per fit). Each CSV has rows:
#
#   Block,                Estimate, SE, LB CI, UB CI, N, Switchers, N.w, Switchers.w
#   Effect_1 .. Effect_K
#   Average_Total_Effect
#   Placebo_1 .. Placebo_L
#
# For each CSV:
#   * Plot relative time on x-axis: Placebo_L -> -L, Reference -> 0 (est=0,
#     no CI), Effect_K -> +K.
#   * Y-axis: estimate with 95% CI errorbars.
#   * Vertical line at x = 0; horizontal line at y = 0.
#   * Top-left annotation: "ATE: <est> (SE <se>)" from Average_Total_Effect row.
#
# Outputs are written to OUT_DIR (default: a `plots_R/` sibling of the CSVs)
# so the original Python-generated PNGs are not overwritten.
#
# Env vars (all optional, sensible defaults provided):
#   IN_DIR   directory of dCDH_*.csv files
#   OUT_DIR  directory to write PNGs
################################################################################

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

# ---- Paths ------------------------------------------------------------------
main_path <- "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires"
default_in <- file.path( main_path, "proj_bureaucrats_farms/tex/paper/tables")

in_dir  <- Sys.getenv("IN_DIR",  default_in)
out_dir <- file.path( main_path, "proj_bureaucrats_farms/tex/paper/figures")

if (!dir.exists(in_dir)) {
  stop("Input dir does not exist: ", in_dir,
       "\nSet IN_DIR env var to override.")
}
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("[plot] IN_DIR  = ", in_dir,  "\n", sep = "")
cat("[plot] OUT_DIR = ", out_dir, "\n", sep = "")

# ---- Title derivation -------------------------------------------------------
# basename = e.g. "dCDH_downup_ac_pop_reset12_actrend"
pretty_title <- function(basename) {
  s <- sub("^dCDH_", "", basename)

  treat <- if (grepl("downup_ac_pop", s)) "downup_ac_pop" else "downup_ac"
  s <- sub(paste0(treat, "_?"), "", s)

  reset <- if (grepl("noreset", s)) {
    "no reset"
  } else if (grepl("reset6", s)) {
    "reset 6"
  } else if (grepl("reset12", s)) {
    "reset 12"
  } else {
    "?"
  }
  s <- sub("(noreset|reset6|reset12)_?", "", s)

  fe <- if (grepl("actrend", s)) {
    "with ac×monthyear FE"
  } else if (grepl("notrend", s)) {
    "without ac×monthyear FE"
  } else {
    "?"
  }

  paste(treat, "·", reset, "·", fe)
}

# ---- CSV -> plot ------------------------------------------------------------
make_plot_df <- function(csv_path) {
  d <- fread(csv_path)

  effects  <- d[grepl("^Effect_[0-9]+$",  Block)]
  placebos <- d[grepl("^Placebo_[0-9]+$", Block)]

  effects[,  k := as.integer(sub("Effect_",  "", Block))]
  placebos[, k := as.integer(sub("Placebo_", "", Block))]

  setorder(effects,  k)
  setorder(placebos, k)

  pre <- data.table(
    rel_time = -placebos$k,
    estimate = placebos$Estimate,
    ci_lo    = placebos$`LB CI`,
    ci_hi    = placebos$`UB CI`,
    kind     = "pre"
  )
  ref <- data.table(
    rel_time = 0L,
    estimate = 0,
    ci_lo    = 0,
    ci_hi    = 0,
    kind     = "ref"
  )
  post <- data.table(
    rel_time = effects$k,
    estimate = effects$Estimate,
    ci_lo    = effects$`LB CI`,
    ci_hi    = effects$`UB CI`,
    kind     = "post"
  )

  rbind(pre, ref, post)
}

ate_annotation <- function(csv_path) {
  d <- fread(csv_path)
  ate_row <- d[Block == "Average_Total_Effect"]
  if (nrow(ate_row) == 0L) return(NA_character_)
  sprintf("ATE: %.3f (SE %.3f)",
          ate_row$Estimate[1L], ate_row$SE[1L])
}

plot_one <- function(csv_path, out_path) {
  pdat <- make_plot_df(csv_path)
  ann  <- ate_annotation(csv_path)
  ttl  <- pretty_title(tools::file_path_sans_ext(basename(csv_path)))

  # Errorbar invisible at the reference period (CI=0).
  p <- ggplot(pdat, aes(x = rel_time, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey60") +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey60") +
    geom_errorbar(
      data = pdat[kind != "ref"],
      aes(ymin = ci_lo, ymax = ci_hi),
      width = 0.0, linewidth = 0.6
    ) +
    geom_point(size = 2.2) +
    scale_x_continuous(
      breaks = sort(unique(pdat$rel_time)),
      minor_breaks = NULL
    ) +
    labs(
      title = ttl,
      x = "Time from Treatment",
      y = "Estimate"
    ) +
    theme_classic(base_size = 12) +
    theme(
      plot.title = element_text(size = 11),
      panel.grid.major.y = element_line(colour = "grey92")
    )

  # Top-left ATE annotation
  if (!is.na(ann)) {
    p <- p + geom_label(
      data = data.frame(x = -Inf, y = Inf, lab = ann),
      aes(x = x, y = y, label = lab),
      hjust = -0.05, vjust = 1.2,
      label.size = 0,
      fill = "white",
      alpha = 0.85,
      size = 3.6,
      inherit.aes = FALSE
    )
  }

  ggsave(out_path, plot = p, width = 7, height = 4.5, dpi = 200)
  cat("[plot] wrote ", out_path, "\n", sep = "")
}

# ---- Run over all dCDH_*.csv -----------------------------------------------
csvs <- list.files(in_dir, pattern = "^dCDH_.*\\.csv$", full.names = TRUE)
if (length(csvs) == 0L) {
  warning("No dCDH_*.csv files found in ", in_dir)
}

for (f in csvs) {
  out_path <- file.path(out_dir, paste0(tools::file_path_sans_ext(basename(f)), ".png"))
  tryCatch(plot_one(f, out_path),
           error = function(e) {
             message("Failed on ", basename(f), ": ", conditionMessage(e))
           })
}

cat("\nDone. ", length(csvs), " CSVs processed.\n", sep = "")
