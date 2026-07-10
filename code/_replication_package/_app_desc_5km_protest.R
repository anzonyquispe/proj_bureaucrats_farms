################################################################################

rm(list = ls())
library(data.table)
library(dplyr)
library(fixest)
library(ggfixest)
library(marginaleffects)
library(haven)

################################################################################

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


################################################################################
########################## Import Data ########################################

# 1. Read data
path1 <- file.path( int_farms, 'stacked_data_protest_sample.csv' )
dt <- fread( path1)
ghs <- as.data.table(read_dta(file.path( int_farms, "ghs_grid_classification_2000.dta")))
# Set keys for fast join
setkey(dt,  unique_small_grid_id)
setkey(ghs, unique_small_grid_id)

# Left join + filter in one chained call
dt <- ghs[dt][is_rural == 1]


dt[, prov := .GRP, by = .(province)]
dt[, legis.govyear := .GRP, by = .(province, election_year)]
names(dt)
path1 <- file.path(int_farms, "rice_moderators.dta")
rice_mods <- read_stata(path1)

dt <- merge(dt, rice_mods, all.x = TRUE, by =  c("unique_small_grid_id", "ac_uq_id"))
dt$post <- dt$relative_year_bin >= 0
dt$protest <- dt$post * dt$treat

################################################################################

colsel <- c("unique_small_grid_id", 
            "year", "month", "ac_uq_id", "prov", 
            "ac_area_tr", "cohort", "legis.govyear",
            "relative_year_bin",
            "protest", "countk", "rice_prod_aclvl_ahigh"
            )
results <- list()

for (v in colsel) {
  col <- dt[[v]]
  
  # test columns continuous
  check <- v %in% c("countk", "rice_prod_aclvl_ahigh", "protest", "relative_year_bin") 
  if (check) {
    res <- data.table(
      variable = v,
      mean = mean(col, na.rm = TRUE),
      sd   = sd(col, na.rm = TRUE),
      min  = min(col, na.rm = TRUE),
      max  = max(col, na.rm = TRUE),
      N    = sum(!is.na(col)),
      unique = uniqueN(col)
    )
  } else {
    res <- data.table(
      variable = v,
      mean = NA_real_,
      sd   = NA_real_,
      min  = NA_real_,
      max  = NA_real_,
      N    = sum(!is.na(col)),
      unique = uniqueN(col)
    )
  }
  results[[v]] <- res
}

# Bind into one table
desc_table <- rbindlist(results)
numcol <- ncol(desc_table)
# desc_table[, 2:numcol] <- round(desc_table[, 2:numcol], 3)


library(kableExtra)

# --- Etiquetas legibles (edita a gusto) ---
label_map <- c(
  unique_small_grid_id       = "Grid ID",
  year                       = "Year",
  month                      = "Month",
  relative_year_bin          = "Relative year",
  ac_uq_id                   = "Assembly Constituency (AC)",
  prov                       = "Province",
  ac_area_tr                 = "Protest Area",
  cohort = "Cohort",
  protest                    = "Protest",
  countk                    = "Number of Fires",
  legis.govyear              = "Legislature",
  rice_prod_aclvl_ahigh      = "High Rice production (AC level)"
)

# --- Preparar tabla ---
tex_table <- copy(desc_table)
tex_table[, variable := label_map[variable]]
tex_table <- tex_table[, .(variable, mean, sd, min, max, N, unique)]

# Formato: 3 decimales para estadísticos, enteros con coma para conteos
fmt_num <- function(x) {
  out <- formatC(round(x, 3), format = "f", digits = 3, big.mark = ",")
  out <- sub("\\.?0+$", "", out)   # quita ".000", ".500"->".5", etc.
  ifelse(is.na(x), "", out)
}
fmt_int <- function(x) ifelse(is.na(x), "", formatC(x, format = "d", big.mark = ","))
tex_table[, `:=`(
  mean = fmt_num(mean), sd = fmt_num(sd),
  min  = fmt_num(min),  max = fmt_num(max),
  N = fmt_int(N), unique = fmt_int(unique)
)]

# --- Escribir .tex ---
kbl(tex_table,
    format    = "latex",
    booktabs  = TRUE,
    escape    = FALSE,
    linesep   = "",
    col.names = c("", "Mean", "SD", "Min", "Max", "Observations", "Unique Obs."),
    align     = "lrrrrrr",
    caption   = "Descriptive statistics",
    label     = "app_desc_10_5km_protest") |>
  kable_styling(latex_options = c("hold_position")) |>
  save_kable(file.path(table_farms, "_protest_stacked_descriptive.tex"))






