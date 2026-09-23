#!/usr/bin/env Rscript

# Manually audit the politician FE01 DiD interaction shown in
# cohort_eventtime_fe_sweep_report.pdf.
suppressPackageStartupMessages({
  library(data.table)
  library(haven)
  library(fixest)
})

repo <- normalizePath(getwd(), winslash = "/")
input <- "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms/data_output/intermediate/politicians_characteristics_byprov_m5_p4.dta"
rural_file <- "C:/Users/eunic/Dropbox/sa_fires/proj_bureaucrats_farms/data_output/intermediate/ghs_grid_classification_2000.dta"
table_dir <- file.path(repo, "tables/exploratory_analysis/cohort_eventtime_fe_sweep")
coef_file <- file.path(
  table_dir,
  "politician_byprov_cohorttime_fe01_did_interaction_rural_acpop_all.csv"
)
scalar_file <- file.path(
  table_dir,
  "politician_byprov_cohorttime_fe01_did_interaction_rural_acpop_all_scalars.csv"
)

canonical <- function(x) {
  x <- gsub("(^|[:#])([0-9]+o?\\.)", "\\1", x, perl = TRUE)
  vapply(strsplit(gsub("#", ":", x, fixed = TRUE), ":", fixed = TRUE),
         function(z) paste(sort(z), collapse = ":"), character(1L))
}

make_auditor <- function(beta, vcov, df, post_name) {
  vcov <- vcov[names(beta), names(beta), drop = FALSE]
  term <- function(vars) {
    hit <- names(beta)[canonical(names(beta)) == paste(sort(vars), collapse = ":")]
    stopifnot(length(hit) == 1L)
    hit
  }
  weight <- function(term_sets) {
    w <- setNames(numeric(length(beta)), names(beta))
    for (vars in term_sets) w[term(vars)] <- w[term(vars)] + 1
    w
  }
  lincom <- function(label, w, method = "Joint covariance from one regression") {
    estimate <- sum(w * beta)
    se <- sqrt(drop(t(w) %*% vcov %*% w))
    critical <- qt(.975, df)
    data.table(
      quantity = label, method, estimate, se,
      lower95 = estimate - critical * se,
      upper95 = estimate + critical * se,
      p_value = 2 * pt(-abs(estimate / se), df)
    )
  }
  m <- "downup_ac_pop"
  w_pre <- weight(list(m))
  w_control <- weight(list(m, c(post_name, m)))
  w_treated <- weight(list(
    m, c(post_name, m), c(post_name, "treat"),
    c("treat", m), c(post_name, "treat", m)
  ))
  w_difference <- w_treated - w_control
  treated_var <- drop(t(w_treated) %*% vcov %*% w_treated)
  control_var <- drop(t(w_control) %*% vcov %*% w_control)
  treated_control_cov <- drop(t(w_treated) %*% vcov %*% w_control)
  naive_se <- sqrt(treated_var + control_var)
  difference <- sum(w_difference * beta)
  critical <- qt(.975, df)

  out <- list(
    pre = lincom("Pre expression", w_pre),
    control_post = lincom("Control-post expression", w_control),
    treated_post = lincom("Treated-post expression", w_treated),
    joint_difference = lincom("Treated - control: proper joint test", w_difference),
    independent_difference = data.table(
      quantity = "Treated - control: covariance set to zero",
      method = "Diagnostic only; incorrectly assumes independence",
      estimate = difference, se = naive_se,
      lower95 = difference - critical * naive_se,
      upper95 = difference + critical * naive_se,
      p_value = 2 * pt(-abs(difference / naive_se), df)
    )
  )
  correlation <- treated_control_cov / sqrt(treated_var * control_var)
  lapply(out, function(x) {
    x[, `:=`(
      treated_control_covariance = treated_control_cov,
      treated_control_correlation = correlation
    )]
    x
  })
}

# 1. Reconstruct the existing graph directly from its saved coefficients/VCOV.
saved <- fread(coef_file)[reg == "evreg1"]
saved_beta <- setNames(saved$beta, saved$var)
saved_vcov <- as.matrix(
  saved[, grep("^cov[0-9]+$", names(saved), value = TRUE), with = FALSE]
)
rownames(saved_vcov) <- colnames(saved_vcov) <- saved$var
saved_df <- fread(scalar_file)[reg == "evreg1", df_r][1L]
saved_check <- rbindlist(make_auditor(
  saved_beta, saved_vcov, saved_df, "post_"
))
saved_check[, source := "Saved Stata FE01"]

cat("\nSAVED FE01 RESULTS AND GRAPH AUDIT\n")
print(saved_check[, .(
  quantity, method, estimate, se, lower95, upper95, p_value,
  treated_control_covariance, treated_control_correlation
)])

# 2. Re-estimate the exact FE01 regression from the local analysis data.
vars <- c(
  "unique_small_grid_id", "province", "ac_uq_id", "count", "month", "year",
  "monthyear", "downup_ac_pop", "av_wind_speed", "wind_direction",
  "election_year", "yeargov", "treat", "control_type", "cohort",
  "cohort_id", "cohort_province", "relative_year"
)
dt <- as.data.table(read_dta(input, col_select = all_of(vars)))
setnames(dt, "relative_year", "relative_year_bin")
rural <- as.data.table(read_dta(
  rural_file, col_select = all_of(c("unique_small_grid_id", "is_rural"))
))
dt[rural, is_rural := i.is_rural, on = "unique_small_grid_id"]
dt <- dt[
  is_rural == 1 &
    (year < 2022 | (year == 2022 & month <= 8)) &
    between(relative_year_bin, -5, 4)
]
complete_vars <- c(
  "unique_small_grid_id", "province", "ac_uq_id", "month", "year",
  "monthyear", "election_year", "yeargov", "cohort", "cohort_id",
  "cohort_province", "count", "downup_ac_pop", "av_wind_speed",
  "wind_direction", "treat", "control_type", "relative_year_bin"
)
dt <- na.omit(dt, cols = complete_vars)
dt[, `:=`(
  countk = count * 1000,
  post = as.integer(relative_year_bin >= 0),
  relative_year_bin_aux = relative_year_bin + 6
)]
dt[, grid_cohort := .GRP, by = .(unique_small_grid_id, cohort_id)]
dt[, cohort_event := .GRP, by = .(relative_year_bin_aux, cohort_id)]
dt[, cluster_id := .GRP, by = .(ac_uq_id, election_year, cohort_id)]

stopifnot(
  nrow(dt) == 8133882L,
  uniqueN(dt$cohort_id) == 8L,
  uniqueN(dt$cluster_id) == 2149L
)

fe01 <- feols(
  countk ~ post * treat * downup_ac_pop + wind_direction + av_wind_speed |
    grid_cohort + cohort_event,
  data = dt,
  cluster = ~cluster_id
)

r_check <- rbindlist(make_auditor(
  coef(fe01), vcov(fe01), uniqueN(dt$cluster_id), "post"
))
r_check[, source := "R re-estimation FE01"]

cat("\nR RE-ESTIMATION\n")
print(r_check[, .(
  quantity, method, estimate, se, lower95, upper95, p_value,
  treated_control_covariance, treated_control_correlation
)])

audit <- rbind(saved_check, r_check, use.names = TRUE)
setcolorder(audit, c(
  "source", "quantity", "method", "estimate", "se", "lower95", "upper95",
  "p_value", "treated_control_covariance", "treated_control_correlation"
))
fwrite(audit, file.path(table_dir, "politician_fe01_interaction_manual_audit.csv"))

cat("\nKEY CHECK\n")
cat("Overlapping individual confidence intervals do not test equality.\n")
cat("The proper difference uses the covariance between the two lincom estimates.\n")
cat("The covariance-zero row is shown only to quantify that covariance effect.\n")
