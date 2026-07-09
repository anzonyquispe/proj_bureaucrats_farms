# =============================================================================
# desc_table.R
# -----------------------------------------------------------------------------
# Generate a descriptive statistics table (mean, sd, min, max, N, unique).
#
# Inputs:
#   data       : a data.frame or data.table
#   vars       : character vector of column names to summarize
#   labels     : character vector of pretty labels (same length as vars).
#                If NULL, the column names are used.
#   uniq_vars  : character vector — subset of `vars` for which to compute
#                the count of distinct values. For variables not in this
#                list the "unique" column is left as NA. If NULL, distinct
#                counts are computed for all variables.
#   digits     : decimal places for continuous statistics (default 3)
#   output     : "data.frame" (default), "kable", "latex", or "gt"
#   file       : optional path. If provided and output is "latex" or "kable",
#                the table is written to this file.
#
# Returns:
#   A data.frame (or formatted object) with columns:
#     Variable | Mean | SD | Min | Max | N | Unique
# =============================================================================
# =============================================================================
rm(list = ls())
library(data.table)
library(haven)
# =============================================================================



################################################################################
####################### Setting working directory ##############################

dbox_root <- '/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires'
shell_root <- '/groups/sgulzar/sa_fires'
root <- dbox_root
int_farms <- file.path( root, 'proj_bureaucrats_farms/data_output/intermediate')
table_farms <- file.path(root, 'proj_bureaucrats_farms/tex/paper/tables')
figure_farms <- file.path(root, 'proj_bureaucrats_farms/tex/paper/figures')
# source('/groups/sgulzar/india_forest_land/C_Programs/utils.R')

################################################################################


# =============================================================================


desc_table <- function(data,
                       vars,
                       labels    = NULL,
                       uniq_vars = NULL,
                       digits    = 3,
                       output    = c("data.frame", "kable", "latex", "gt"),
                       file      = NULL) {
  
  output <- match.arg(output)
  
  # ---- Input checks ------------------------------------------------------
  if (!is.data.frame(data)) {
    stop("`data` must be a data.frame or data.table.")
  }
  missing_vars <- setdiff(vars, names(data))
  if (length(missing_vars) > 0) {
    stop("These variables are not in the data: ",
         paste(missing_vars, collapse = ", "))
  }
  if (is.null(labels)) {
    labels <- vars
  } else if (length(labels) != length(vars)) {
    stop("`labels` must have the same length as `vars` (",
         length(vars), " expected, got ", length(labels), ").")
  }
  if (is.null(uniq_vars)) {
    uniq_vars <- character(0)
  } else {
    bad <- setdiff(uniq_vars, vars)
    if (length(bad) > 0) {
      stop("`uniq_vars` must be a subset of `vars`. Not in vars: ",
           paste(bad, collapse = ", "))
    }
  }
  
  # ---- Coerce to data.table for speed ------------------------------------
  dt <- as.data.table(data)
  
  # ---- Number formatters -------------------------------------------------
  # Strip trailing zero decimals: "2,015.000" -> "2,015"; "12.500" stays.
  strip_zero_decimals <- function(s) sub("\\.0+$", "", s)
  fmt_num <- function(x, d) {
    if (is.na(x) || is.nan(x) || is.infinite(x)) return("")
    use_d <- if (abs(x) < 1) 3 else d
    s <- formatC(x, format = "f", digits = use_d, big.mark = ",")
    strip_zero_decimals(s)
  }
  fmt_int <- function(x) {
    if (is.na(x)) return("")
    formatC(x, format = "d", big.mark = ",")
  }
  
  # ---- Build result as character so blanks render cleanly ---------------
  out <- data.table(
    .var          = labels,
    Mean          = "",
    SD            = "",
    Min           = "",
    Max           = "",
    Observations  = "",
    `Unique Obs.` = ""
  )
  
  for (i in seq_along(vars)) {
    v <- vars[i]
    x <- dt[[v]]
    
    if (v %in% uniq_vars) {
      # Min, Max, and Unique count for these variables.
      out[i, `Unique Obs.` := fmt_int(uniqueN(x, na.rm = TRUE))]
    } else {
      # Full summary (no Unique count).
      if (is.numeric(x)) {
        out[i, Mean := fmt_num(mean(x, na.rm = TRUE), digits)]
        out[i, SD   := fmt_num(stats::sd(x, na.rm = TRUE), digits)]
        out[i, Min  := fmt_num(min(x, na.rm = TRUE), digits)]
        out[i, Max  := fmt_num(max(x, na.rm = TRUE), digits)]
      }
      out[i, Observations := fmt_int(sum(!is.na(x)))]
    }
  }
  
  # ---- Output formatting -------------------------------------------------
  if (output == "data.frame") {
    setnames(out, ".var", " ")
    return(as.data.frame(out, check.names = FALSE))
  }
  
  if (output == "kable") {
    if (!requireNamespace("knitr", quietly = TRUE)) {
      stop("Install the `knitr` package to use output = 'kable'.")
    }
    setnames(out, ".var", " ")
    tab <- knitr::kable(out, format = "pipe")
    if (!is.null(file)) writeLines(tab, file)
    return(tab)
  }
  
  if (output == "latex") {
    if (!requireNamespace("kableExtra", quietly = TRUE)) {
      stop("Install the `kableExtra` package to use output = 'latex'.")
    }
    
    # Use explicit col.names so the empty first header survives, and let
    # LaTeX commands in labels pass through (escape = FALSE).
    headers <- c("", "Mean", "SD", "Min", "Max", "Observations", "Unique Obs.")
    stopifnot(length(headers) == ncol(out))
    
    tab <- kableExtra::kbl(
      out,
      format    = "latex",
      booktabs  = TRUE,
      linesep   = "",
      escape    = FALSE,                              # pass through LaTeX
      align     = c("l", rep("r", ncol(out) - 1L)),
      col.names = headers,
      caption   = NULL
    )
    if (!is.null(file)) writeLines(as.character(tab), file)
    return(tab)
  }
  
  if (output == "gt") {
    if (!requireNamespace("gt", quietly = TRUE)) {
      stop("Install the `gt` package to use output = 'gt'.")
    }
    setnames(out, ".var", " ")
    return(gt::gt(out))
  }
}



# =============================================================================
# Example usage
# =============================================================================

path1_link <- file.path( int_farms, '0_master_merge_data_gen.csv' )
dt <- fread( path1_link )[year < 2022 | (year == 2022 & month <= 8 )]
ghs <- as.data.table(read_dta(file.path( int_farms, "ghs_grid_classification_2000.dta")))
dt <- merge(dt, ghs, by = 'unique_small_grid_id', all.x = TRUE)
dt[, prov := .GRP, by = province]
setnames(dt, "count", "count_fires")
dt <- dt[ is_rural == 1, ]


# LaTeX export
desc_table(
  data   = dt,
  vars   = c("unique_small_grid_id", "year", "month", "ac_uq_id", "prov",
             "count_fires", "downup_ac", "av_wind_speed", "wind_direction", "rice_prod_aclvl_ahigh"),
  labels = c("Grid ID", "Year", "Month", "Assembly", "Province",
             "Number of Fires", "Down $\\times$ Up AC", "Average Wind Speed",
             "Wind Direction", "Rice Production"),
  uniq_vars = c("unique_small_grid_id","year", "month", "ac_uq_id", "prov"),
  output    = "latex",
  file      = file.path( table_farms, "descriptives_main.tex")
)



