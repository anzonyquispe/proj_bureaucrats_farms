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

dbox_root <- 'C:/Users/Anzony/Dropbox/sa_fires'
shell_root <- '/groups/sgulzar/sa_fires'
root <- shell_root
int_farms <- file.path( root, 'proj_bureaucrats_farms/data_output/intermediate')
table_farms <- file.path(root, 'proj_bureaucrats_farms/tex/paper/tables')
figure_farms <- file.path(root, 'proj_bureaucrats_farms/tex/paper/figures')
# source('/groups/sgulzar/india_forest_land/C_Programs/utils.R')

################################################################################


################################################################################
########################## Import Data ########################################

# 1. Read data
path1 <- file.path( int_farms, '10_pr_cluster_2022_5km.csv' )
dt <- fread( path1)
ghs <- as.data.table(read_dta(file.path( int_farms, "ghs_grid_classification_2000.dta")))
# Set keys for fast join
setkey(dt,  unique_small_grid_id)
setkey(ghs, unique_small_grid_id)

# Left join + filter in one chained call
dt <- ghs[dt][is_rural == 1]


dt[, prov := .GRP, by = .(province)]
dt[, legis.govyear := .GRP, by = .(province, election_year, yeargov)]
names(dt)
path1 <- file.path(int_farms, "rice_moderators.dta")
rice_mods <- read_stata(path1)

dt <- merge(dt, rice_mods, all.x = TRUE, by =  c("unique_small_grid_id", "ac_uq_id"))
dt$protest <- dt$post * dt$treat
################################################################################

colsel <- c("unique_small_grid_id", 
            "year", "month", "ac_uq_id", "prov", "ac_area_tr",
            "protest", "count.k", "legis.govyear",
            "rice_area_aclvl_ahigh", "rice_harvarea_aclvl_ahigh", 
            "rice_prod_aclvl_ahigh")
results <- list()

for (v in colsel) {
  col <- dt[[v]]
  
  if (is.numeric(col)) {
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
desc_table[, 2:numcol] <- round(desc_table[, 2:numcol], 3)


fwrite(desc_table, file.path(int_farms, "_app_desc_10_5km_protest.csv"))







