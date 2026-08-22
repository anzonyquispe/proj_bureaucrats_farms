#!/usr/bin/env Rscript

# Independent R/fixest replication of the production protest interaction model.
# The input is streamed because the decompressed stack contains ~88m rows.

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(ggplot2)
  library(haven)
  library(readr)
})

parse_args <- function(x) {
  defaults <- list(
    input = "C:/Users/eunic/OneDrive/Documents/stacked_data_protest5km_election_sameterm.csv.xz",
    rural = "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms/data_output/intermediate/ghs_grid_classification_2000.dta",
    output = "",
    cache = "C:/Users/eunic/OneDrive/Documents/protest_fixest_cache",
    sample_share = 1,
    threads = max(1L, parallel::detectCores(logical = FALSE) - 1L)
  )
  i <- 1L
  while (i <= length(x)) {
    key <- sub("^--", "", x[[i]])
    if (!key %in% names(defaults) || i == length(x)) {
      stop("Unknown or incomplete argument: ", x[[i]], call. = FALSE)
    }
    defaults[[key]] <- x[[i + 1L]]
    i <- i + 2L
  }
  defaults$sample_share <- as.numeric(defaults$sample_share)
  defaults$threads <- as.integer(defaults$threads)
  if (!is.finite(defaults$sample_share) || defaults$sample_share <= 0 ||
      defaults$sample_share > 1) {
    stop("--sample_share must be in (0, 1].", call. = FALSE)
  }
  defaults
}

find_repo <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = FALSE)
  repeat {
    marker <- file.path(current, "code", "_stacked_downup_replication")
    if (dir.exists(marker)) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) return("")
    current <- parent
  }
}

opt <- parse_args(commandArgs(trailingOnly = TRUE))
repo <- find_repo()
if (!nzchar(opt$output)) {
  if (!nzchar(repo)) stop("Supply --output when the repository is not detected.")
  opt$output <- file.path(
    repo, "tables", "exploratory_analysis", "protest_fixest_replication"
  )
}
dir.create(opt$output, recursive = TRUE, showWarnings = FALSE)
dir.create(opt$cache, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(opt$input)) stop("Missing input: ", opt$input, call. = FALSE)
if (!file.exists(opt$rural)) stop("Missing rural lookup: ", opt$rural, call. = FALSE)

setDTthreads(opt$threads)
setFixest_nthreads(opt$threads)

rural <- as.data.table(read_dta(opt$rural))
stopifnot(all(c("unique_small_grid_id", "is_rural") %in% names(rural)))
rural_ids <- unique(rural[is_rural == 1, as.integer(unique_small_grid_id)])
rm(rural)
gc()

needed <- c(
  "unique_small_grid_id", "province", "ac_uq_id", "count", "month", "year",
  "monthyear", "downup_ac_pop", "av_wind_speed", "wind_direction",
  "election_year", "treat", "cohort", "relative_year",
  "cohort_election_year", "cohort_id", "cohort_term_start",
  "cohort_analysis_max"
)

run_id <- paste0(
  "share_", gsub("\\.", "p", format(opt$sample_share, scientific = FALSE)),
  "_", format(Sys.time(), "%Y%m%d_%H%M%S")
)
part_dir <- file.path(opt$cache, run_id)
dir.create(part_dir, recursive = TRUE, showWarnings = FALSE)
part_number <- 0L
input_rows <- 0
retained_rows <- 0

province_codes <- c(
  "Bihar" = 1L, "Haryana" = 2L, "Punjab" = 3L,
  "Punjab_IND" = 3L, "Uttar Pradesh" = 4L
)

callback <- SideEffectChunkCallback$new(function(chunk, pos) {
  setDT(chunk)
  input_rows <<- input_rows + nrow(chunk)

  invalid_term <- chunk[
    monthyear < cohort_term_start |
      monthyear > cohort_analysis_max |
      cohort_analysis_max - cohort_term_start < 0 |
      cohort_analysis_max - cohort_term_start > 59
  ]
  if (nrow(invalid_term)) stop("Rows outside a valid government term detected.")
  if (chunk[, any(relative_year != floor((monthyear - cohort) / 12))]) {
    stop("relative_year is not defined from the protest cohort month.")
  }

  chunk <- chunk[
    unique_small_grid_id %in% rural_ids &
      (year < 2022 | (year == 2022 & month <= 8)) &
      between(relative_year, -4, 1)
  ]
  if (opt$sample_share < 1 && nrow(chunk)) {
    # Deterministic sampling at the complete grid x cohort_id unit level.
    threshold <- floor(opt$sample_share * 100000)
    unit_hash <- (
      as.double(chunk$unique_small_grid_id) * 1009 +
        as.double(chunk$cohort_id) * 9176
    ) %% 100000
    chunk <- chunk[unit_hash < threshold]
  }
  if (!nrow(chunk)) return(invisible(NULL))

  prov <- unname(province_codes[as.character(chunk$province)])
  if (anyNA(prov)) stop("Unknown province value encountered.")
  chunk[, `:=`(
    countk = as.numeric(count) * 1000,
    post = as.integer(relative_year >= 0),
    grid_cohort = as.double(unique_small_grid_id) * 1000 + cohort_id,
    relativeyear_cohort = as.double(relative_year + 10) * 1000 + cohort_id,
    province_election =
      (as.double(prov) * 1000 + cohort_id) * 10000 + election_year,
    province_cohort = as.double(prov) * 1000 + cohort_id,
    ac_elec_yr =
      (as.double(ac_uq_id) * 10000 + cohort_election_year) * 1000 + cohort_id
  )]

  compact <- chunk[, .(
    countk, post, treat = as.integer(treat),
    downup_ac_pop = as.integer(downup_ac_pop),
    wind_direction = as.numeric(wind_direction),
    av_wind_speed = as.numeric(av_wind_speed),
    relative_year = as.integer(relative_year), monthyear = as.integer(monthyear),
    grid_cohort, relativeyear_cohort, province_election, province_cohort,
    ac_elec_yr
  )]
  retained_rows <<- retained_rows + nrow(compact)
  part_number <<- part_number + 1L
  saveRDS(
    compact,
    file.path(part_dir, sprintf("part_%05d.rds", part_number)),
    compress = FALSE
  )
  if (part_number %% 10L == 0L) {
    message(
      "chunks=", part_number, " input_rows=", format(input_rows, big.mark = ","),
      " retained_rows=", format(retained_rows, big.mark = ",")
    )
  }
  invisible(NULL)
})

message("Streaming: ", opt$input)
read_csv_chunked(
  opt$input,
  callback = callback,
  chunk_size = 500000,
  col_types = cols_only(
    unique_small_grid_id = col_integer(),
    province = col_character(),
    ac_uq_id = col_integer(),
    count = col_double(),
    month = col_integer(),
    year = col_integer(),
    monthyear = col_integer(),
    downup_ac_pop = col_integer(),
    av_wind_speed = col_double(),
    wind_direction = col_double(),
    election_year = col_double(),
    treat = col_integer(),
    cohort = col_integer(),
    relative_year = col_integer(),
    cohort_election_year = col_double(),
    cohort_id = col_integer(),
    cohort_term_start = col_integer(),
    cohort_analysis_max = col_integer()
  ),
  show_col_types = FALSE,
  progress = interactive()
)

part_files <- list.files(part_dir, pattern = "^part_[0-9]+\\.rds$", full.names = TRUE)
if (!length(part_files)) stop("No observations survived the sample filters.")
message("Combining ", length(part_files), " compact chunks.")
dt <- rbindlist(lapply(part_files, readRDS), use.names = TRUE)

dt[, `:=`(
  has_pre = any(relative_year < 0),
  has_post = any(relative_year >= 0)
), by = grid_cohort]
units_before <- uniqueN(dt$grid_cohort)
units_balanced <- uniqueN(dt[has_pre & has_post, grid_cohort])
dt <- dt[has_pre & has_post]
dt[, c("has_pre", "has_post") := NULL]

if (!nrow(dt)) stop("No complete pre/post grid-cohort units remain.")
stopifnot(
  dt[, all(relative_year >= -4 & relative_year <= 1)],
  dt[, all(post == as.integer(relative_year >= 0))],
  dt[, all(treat %in% 0:1)],
  dt[, all(downup_ac_pop %in% 0:1)]
)

message(
  "Estimation rows=", format(nrow(dt), big.mark = ","),
  "; complete units=", format(units_balanced, big.mark = ","),
  " of ", format(units_before, big.mark = ",")
)

# `post` is exactly absorbed by relativeyear_cohort, while `treat` is exactly
# absorbed by grid_cohort. Stata/reghdfe omits both. Writing the identified RHS
# explicitly prevents fixest's numerical collinearity detector from retaining
# near-zero residualized versions of these two terms in very large panels.
model <- feols(
  countk ~ downup_ac_pop + post:treat + post:downup_ac_pop +
    treat:downup_ac_pop + post:treat:downup_ac_pop +
    wind_direction + av_wind_speed |
    grid_cohort + relativeyear_cohort + province_election +
    province_cohort[[monthyear]],
  cluster = ~ac_elec_yr,
  data = dt,
  nthreads = opt$threads,
  mem.clean = TRUE,
  ssc = ssc(
    K.adj = TRUE, K.fixef = "nested", G.adj = TRUE,
    G.df = "min", t.df = "min"
  )
)

b <- coef(model)
v <- vcov(model)

find_term <- function(parts) {
  candidates <- names(b)[vapply(
    strsplit(names(b), ":", fixed = TRUE),
    function(x) setequal(x, parts), logical(1)
  )]
  if (length(candidates) != 1L) {
    stop("Cannot uniquely identify coefficient: ", paste(parts, collapse = ":"))
  }
  candidates
}

t_post_treat <- find_term(c("post", "treat"))
t_post_down <- find_term(c("post", "downup_ac_pop"))
t_treat_down <- find_term(c("treat", "downup_ac_pop"))
t_triple <- find_term(c("post", "treat", "downup_ac_pop"))

contrast <- function(label, terms = character()) {
  w <- setNames(numeric(length(b)), names(b))
  if (length(terms)) w[terms] <- 1
  estimate <- sum(w * b)
  se <- sqrt(drop(t(w) %*% v %*% w))
  df <- degrees_freedom(model, type = "t")
  data.table(
    estimand = label,
    estimate = estimate,
    std_error = se,
    lower90 = estimate - qt(.95, df) * se,
    upper90 = estimate + qt(.95, df) * se,
    lower95 = estimate - qt(.975, df) * se,
    upper95 = estimate + qt(.975, df) * se,
    p_value = if (se > 0) 2 * pt(-abs(estimate / se), df) else NA_real_
  )
}

audit <- rbindlist(list(
  contrast("control_pre"),
  contrast("control_post", t_post_down),
  contrast(
    "treated_post",
    c(t_post_treat, t_post_down, t_treat_down, t_triple)
  ),
  contrast("treated_minus_control_post", c(t_post_treat, t_treat_down, t_triple))
))
audit[, `:=`(
  sample_share = opt$sample_share,
  observations = nobs(model),
  clusters = uniqueN(dt$ac_elec_yr),
  complete_grid_cohort_units = units_balanced
)]

tag <- if (opt$sample_share == 1) "full" else {
  paste0("sample_", gsub("\\.", "p", format(opt$sample_share, scientific = FALSE)))
}
audit_path <- file.path(opt$output, paste0("protest_fixest_interaction_", tag, ".csv"))
coef_path <- file.path(opt$output, paste0("protest_fixest_coefficients_", tag, ".csv"))
plot_path <- file.path(opt$output, paste0("protest_fixest_interaction_", tag, ".png"))
summary_path <- file.path(opt$output, paste0("protest_fixest_model_", tag, ".txt"))

fwrite(audit, audit_path)
fwrite(as.data.table(coeftable(model), keep.rownames = "term"), coef_path)
capture.output(summary(model), file = summary_path)

plot_dt <- audit[estimand %in% c("control_pre", "control_post", "treated_post")]
plot_dt[, x := c(.9, 3.5, 3.5)]
plot_dt[, group := c("Before protest", "No protest", "Protest")]
diff_row <- audit[estimand == "treated_minus_control_post"]

p <- ggplot(plot_dt, aes(x, estimate, shape = group)) +
  geom_errorbar(aes(ymin = lower95, ymax = upper95), width = .08) +
  geom_errorbar(aes(ymin = lower90, ymax = upper90), width = .16, linewidth = 1) +
  geom_segment(
    data = plot_dt[estimand != "control_pre"],
    aes(x = .95, xend = 3.45, y = 0, yend = estimate),
    inherit.aes = FALSE,
    arrow = arrow(length = grid::unit(.12, "inches"))
  ) +
  geom_point(size = 3) +
  geom_hline(yintercept = 0, colour = "black", linewidth = .4) +
  annotate(
    "text", x = 4.55,
    y = mean(plot_dt[estimand != "control_pre", estimate]),
    label = sprintf("p = %.3f", diff_row$p_value), hjust = 0
  ) +
  annotate("text", x = .9, y = 0, label = "Before protest", vjust = -1) +
  annotate("text", x = 3.5, y = plot_dt[estimand == "control_post", estimate],
           label = "No Protest", hjust = 1.1, vjust = -1) +
  annotate("text", x = 3.5, y = plot_dt[estimand == "treated_post", estimate],
           label = "Protest", hjust = -.1, vjust = -1) +
  scale_shape_manual(values = c(16, 16, 17)) +
  coord_cartesian(xlim = c(.3, 5.5)) +
  labs(
    x = NULL,
    y = "Effect of Down>Up on Number of Fires (x 1,000)",
    caption = "Thin/thick intervals are 95%/90% cluster-robust confidence intervals."
  ) +
  theme_classic(base_size = 12) +
  theme(
    axis.text.x = element_blank(), axis.ticks.x = element_blank(),
    legend.position = "none"
  )
ggsave(plot_path, p, width = 8, height = 4.5, dpi = 300)

print(audit)
message("Audit CSV: ", audit_path)
message("Coefficient CSV: ", coef_path)
message("Model summary: ", summary_path)
message("Interaction plot: ", plot_path)
