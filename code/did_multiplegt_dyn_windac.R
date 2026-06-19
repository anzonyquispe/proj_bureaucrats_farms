# Load library
library(haven)
library(DIDmultiplegtDYN)
library(polars)
library(data.table)

root      <- "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires"   # $root
int_farms <- file.path(root, "proj_bureaucrats_farms/data_output/intermediate")

# ---- 1. import the master CSV ----
keep_vars <- c(
  "unique_small_grid_id", 'province', "year", "month", "monthyear", "downup_ac",
  "count", "ac_uq_id", "av_wind_speed", "wind_direction"
)
master <- fread(
  file.path(int_farms, paste0("0_master_merge_data_gen.csv") )
)[, ..keep_vars]

# ---- 2. load the .dta lookups, coerce to data.table ----
rural <- as.data.table(
  read_dta(file.path(int_farms, "ghs_grid_classification_2000.dta"))
)[, .(unique_small_grid_id, is_rural)]

more1ac <- as.data.table(
  read_dta(file.path(int_farms, "grids_with_more_1_ac.dta"))
)

# ---- 3. merge m:1 rural  +  keep if _merge == 3  (inner join) ----
master <- merge(
  master, rural,
  by = "unique_small_grid_id",
  all.x = TRUE          # inner join: keeps only matched rows (_merge == 3)
)

# keep if is_rural == 1
master <- master[is_rural == 1]


# ---- 4. merge m:1 grids_with_more_1_ac (left), drop if dpl_ac == 1 ----
master <- merge(
  master, more1ac,
  by = "unique_small_grid_id",
  all.x = TRUE         # left join: keep all master rows
)

# drop if dpl_ac == 1  (Stata keeps dpl_ac == 0 AND unmatched/missing)
master <- master[is.na(dpl_ac) | dpl_ac != 1]

# ---- 5. gen countk = count * 1000 ----
master[, countk := count * 1000]

# ---- 6. keep if year < 2022 | (year == 2022 & month <= 8) ----
master <- master[year < 2022 | (year == 2022 & month <= 8)]

# ---- 7. final variable selection ----
keep_vars <- c(
  "unique_small_grid_id", 'province', "year", "month", "monthyear",
  "count", "ac_uq_id", "av_wind_speed", "wind_direction",
  "countk", "downup_ac"
)
table(master$province)/1000000
testdata <- master[province == 'Haryana' & year <= 2015, ..keep_vars]


result <- did_multiplegt_dyn(
  df        = master,
  outcome   = "countk",
  group     = "unique_small_grid_id",
  time      = "monthyear",
  controls = c("av_wind_speed", "wind_direction")
  treatment = "downup_ac",
  effects   = 6,
  placebo   = 6,
  trends_nonparam = 'ac_uq_id'
)



