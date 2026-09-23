# Q-weighted politician event study, following Wing-Freedman-Hollingsworth.
suppressPackageStartupMessages({
  library(data.table)
  library(haven)
  library(fixest)
})
source("code/_stacked_downup_replication/exploratory_analysis/plot_did_interactions.R")

input <- "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms/data_output/intermediate/politicians_characteristics_byprov_m5_p4.dta"
output <- "tables/exploratory_analysis/politician_byprov_stack_weights"
figure_output <- "figures/exploratory_analysis/politician_byprov_stack_weights"
event_window <- -5:4
dir.create(output, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_output, recursive = TRUE, showWarnings = FALSE)

cols <- c(
  "unique_small_grid_id", "ac_uq_id", "election_year", "monthyear",
  "cohort_id", "relative_year", "treat", "count",
  "wind_direction", "av_wind_speed", "province", "cohort_year",
  "cohort_month", "downup_ac_pop"
)
dt <- as.data.table(read_dta(input, col_select = all_of(cols)))
dt <- na.omit(dt, cols = cols)
dt <- dt[between(relative_year, min(event_window), max(event_window))]

# All treat == 0 observations are never-treated controls in their stack.
# Keep every cohort and document the event-time coverage of each subexperiment.
selection <- dt[, .(
  province = first(province),
  cohort_year = first(cohort_year),
  cohort_month = first(cohort_month),
  min_event = min(relative_year),
  max_event = max(relative_year),
  treated_full_window = all(event_window %in% relative_year[treat == 1]),
  control_full_window = all(event_window %in% relative_year[treat == 0])
), by = cohort_id]
selection[, full_window := treated_full_window & control_full_window]
selection[, included := TRUE]
selection[, reason := paste0(
  "Included: contributes from event time ", min_event, " to ", max_event
)]
setorder(selection, cohort_id)
fwrite(selection, file.path(output, "cohort_coverage.csv"))
cohort_ids <- selection$cohort_id
cat("Included cohort_id:", paste(sort(cohort_ids), collapse = ", "), "\n")

# Q = (treated share of the cohort)/(control share of the cohort), by event time.
dt[, `:=`(N_t = sum(treat), N_c = sum(1 - treat)), by = relative_year]
dt[, `:=`(n_t = sum(treat), n_c = sum(1 - treat)),
   by = .(cohort_id, relative_year)]
dt[, stack_weight := fifelse(treat == 1, 1, (n_t / N_t) / (n_c / N_c))]

# Verify that weighted control cohort shares equal treated cohort shares.
check <- dt[, .(mass = sum(stack_weight)), by = .(relative_year, cohort_id, treat)]
check[, share := mass / sum(mass), by = .(relative_year, treat)]
wide <- dcast(check, relative_year + cohort_id ~ treat, value.var = "share")
stopifnot(max(abs(wide[["0"]] - wide[["1"]])) < 1e-10)

# Fixed-effect and clustering identifiers used by the requested specifications.
dt[, `:=`(
  countk = count * 1000,
  grid_cohort = .GRP
), by = .(unique_small_grid_id, cohort_id)]
dt[, cluster_id := .GRP, by = .(ac_uq_id, cohort_id)]
dt[, post := as.integer(relative_year >= 0)]

models <- list(
  original = feols(
    countk ~ i(relative_year, treat, ref = -1) +
      wind_direction + av_wind_speed | treat + relative_year,
    data = dt, weights = ~stack_weight, cluster = ~cluster_id
  ),
  fe01 = feols(
    countk ~ i(relative_year, treat, ref = -1) +
      wind_direction + av_wind_speed | grid_cohort,
    data = dt, weights = ~stack_weight, cluster = ~cluster_id
  ),
  fe05 = feols(
    countk ~ i(relative_year, treat, ref = -1) +
      wind_direction + av_wind_speed |
      grid_cohort + province^cohort_id^election_year,
    data = dt, weights = ~stack_weight, cluster = ~cluster_id
  )
)

# Weighted DiD interactions corresponding to the established interaction graph.
did_models <- list(
  original = feols(
    countk ~ post * treat * downup_ac_pop +
      wind_direction + av_wind_speed | treat + relative_year,
    data = dt, weights = ~stack_weight, cluster = ~cluster_id
  ),
  fe01 = feols(
    countk ~ post * treat * downup_ac_pop +
      wind_direction + av_wind_speed | grid_cohort,
    data = dt, weights = ~stack_weight, cluster = ~cluster_id
  ),
  fe05 = feols(
    countk ~ post * treat * downup_ac_pop +
      wind_direction + av_wind_speed |
      grid_cohort + province^cohort_id^election_year,
    data = dt, weights = ~stack_weight, cluster = ~cluster_id
  )
)

fwrite(unique(dt[, .(cohort_id, relative_year, treat, n_t, n_c, N_t, N_c,
                     stack_weight)])[order(cohort_id, relative_year, treat)],
       file.path(output, "stack_weights.csv"))

# Export coefficients and covariance inputs for plotting_event_studies.R.
labels <- c(original = "Original stacked FE", fe01 = "FE 01", fe05 = "FE 05")
ymean <- dt[treat == 1 & relative_year <= -1, mean(countk)]
fwrite(data.table(
  observations = nrow(dt), clusters = uniqueN(dt$cluster_id), ymean = ymean,
  cohorts = paste(sort(cohort_ids), collapse = ", "),
  min_control_weight = min(dt[treat == 0, stack_weight]),
  max_control_weight = max(dt[treat == 0, stack_weight])
), file.path(output, "analysis_metadata.csv"))
coef_tables <- lapply(names(models), function(id) {
  model <- models[[id]]
  terms <- grep("^relative_year::-?[0-9]+:treat$", names(coef(model)), value = TRUE)
  times <- as.integer(sub("^relative_year::(-?[0-9]+):treat$", "\\1", terms))
  terms <- terms[order(times)]
  vc <- vcov(model)[terms, terms, drop = FALSE]
  fwrite(
    cbind(
      data.table(ymean = ymean, beta = unname(coef(model)[terms])),
      as.data.table(unname(vc))
    ),
    file.path(output, paste0(id, "_plot_input.csv"))
  )

  out <- as.data.table(coeftable(model), keep.rownames = "term")[term %in% terms]
  out[, `:=`(
    specification = id,
    label = labels[[id]],
    event_time = as.integer(sub("^relative_year::(-?[0-9]+):treat$", "\\1", term)),
    ci_lower = Estimate - 1.96 * `Std. Error`,
    ci_upper = Estimate + 1.96 * `Std. Error`
  )]
  out[]
})
fwrite(rbindlist(coef_tables)[order(specification, event_time)],
       file.path(output, "weighted_event_studies.csv"))

interaction_tables <- rbindlist(lapply(names(did_models), function(id) {
  results <- interaction_from_fixest(did_models[[id]])
  results[, `:=`(specification = id, label = labels[[id]])]
  plot_did_interaction(
    results,
    file.path(figure_output, paste0("politician_qweight_", id, "_interaction.png")),
    type = "politician"
  )
  results
}), use.names = TRUE)
fwrite(interaction_tables, file.path(output, "weighted_did_interactions.csv"))

etable(
  setNames(models, unname(labels)), keep_raw = "relative_year::", tex = TRUE,
  headers = list(Specification = unname(labels)),
  fitstat = ~n + r2 + wr2, digits = 3, replace = TRUE,
  file = file.path(output, "weighted_event_study_table.tex")
)

invisible(lapply(models, summary))
