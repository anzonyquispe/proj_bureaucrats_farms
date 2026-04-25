################################################################################

rm(list = ls())
library(data.table)
library(doParallel)
library(dplyr)
library(HonestDiD)
library(ggplot2)

################################################################################

################################################################################
####################### Setting working directory ##############################

# dbox_root <- 'C:/Users/rjbar/Saadgulzar Dropbox/rbarreraf@fen.uchile.cl/sa_fires'
dbox_root <- '/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires'
shell_root <- '/groups/sgulzar/sa_fires'

# Auto-detect environment: use shell if available, otherwise dbox
if (dir.exists(shell_root)) {
  root <- shell_root
  cat("Running on cluster (shell)\n")
} else {
  root <- dbox_root
  cat("Running locally (dbox)\n")
}

int_farms <- file.path( root, 'proj_bureaucrats_farms/data_output/intermediate')
table_farms <- file.path(root, 'proj_bureaucrats_farms/tex/paper/tables')
figure_farms <- file.path(root, 'proj_bureaucrats_farms/tex/paper/figures')

################################################################################



################################################################################
####################### Parallel Computing Setting #############################

ncores <- max(1, parallel::detectCores() - 1)
cl <- makeCluster(ncores)
registerDoParallel(cl)

path.plot <- file.path( root, "proj_bureaucrats_farms/code/tools/plot_event_studies.R" )
source( path.plot )


################################################################################



################################################################################
options(datatable.print.nrows = 100)

# Inspecting the images event studies
df <- fread(file.path(table_farms, "main_event_study_rural.csv"))
kl <- 1
file_base <- paste0("main_event_study_rural_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(6:1, 7:12), c(  3, 4, 10:5, 11:16)  ]
agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                  xlab = "Time from Treatment (months)", 
                  ylab = "Effect on Number of Fires (in 1,000 units)",
                  omitted_period = 0, honest = TRUE, 
                  extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                  extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
mods <- c('riceA', 'riceHA', 'riceP')
for (kl in 2:4){
  i <- kl-1
  file_base <- paste0("main_event_study_rural_", mods[i])
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(18:13, 19:24), c(  2, 3, 4, 22:17, 23:28)  ]
  agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                    xlab = "Time from Treatment (months)", 
                    ylab = "Effect on Number of Fires (in 1,000 units)",
                    omitted_period = 0, honest = FALSE)
}



# Event studies of the politicians
df <- fread(file.path(table_farms, "_app_16_polischar_fe12_evst_all_rural.csv"))
kl <- 1
file_base <- paste0("_app_16_polischar_fe12_evst_all_rural_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(13:21), c(  3, 4, 17:25)  ]
agregation_result(ev, numPrePeriods=5, numPostPeriods = 5, M = 1, omitted_period = -1, honest = FALSE)
mods <- c('downup', 'riceA', 'riceHA', 'riceP')
for (kl in 2:5){
  i <- kl-1
  file_base <- paste0("_app_16_polischar_fe12_evst_all_rural_", mods[i], "_", kl)
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(33:41), c(  3, 4, 37:45)  ]
  agregation_result(ev, numPrePeriods=5, numPostPeriods = 5, M = 1, omitted_period = -1, honest = FALSE)
}


# Event studies of the Protests
df <- fread(file.path(table_farms, "_app_17_5km_fe12_evst_all_rural.csv"))
kl <- 1
file_base <- paste0("_app_17_5km_fe12_evst_all_rural_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(13:21), c(  3, 4, 17:25)  ]
agregation_result(ev, numPrePeriods=8, numPostPeriods = 2, M = 1, omitted_period = -1, honest = FALSE)
mods <- c('downup', 'riceA', 'riceHA', 'riceP')
for (kl in 2:5){
  i <- kl-1
  file_base <- paste0("_app_17_5km_fe12_evst_all_rural_", mods[i], "_", kl)
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(33:41), c(  3, 4, 37:45)  ]
  agregation_result(ev, numPrePeriods=8, numPostPeriods = 2, M = 1, omitted_period = -1, honest = FALSE)
}


################################################################################