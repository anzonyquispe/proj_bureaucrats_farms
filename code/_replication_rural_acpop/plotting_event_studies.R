################################################################################

rm(list = ls())
library(data.table)
library(doParallel)
library(dplyr)
library(HonestDiD)
library(ggplot2)
library(panelView)

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

tools_root <- "/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/_replication_rural/tools"
path.plot <- file.path( tools_root, "plot_event_studies.R" )
source( path.plot )


################################################################################



################################################################################
options(datatable.print.nrows = 100)

# Inspecting the images event studies
df <- fread(file.path(table_farms, "main_event_study_rural_acpop.csv"))
kl <- 1
file_base <- paste0("main_event_study_rural_acpop_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(6:1, 7:12), c(  3, 4, 10:5, 11:16)  ]
agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                  xlab = "Time from Treatment (months)", 
                  ylab = "Effect on Number of Fires (in 1,000 units)",
                  omitted_period = 0, honest = TRUE, 
                  ylim_ori = c(-30, 20), ylim_rot = c(-40, 30),
                  extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                  extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
mods <- c('riceA', 'riceHA', 'riceP')
for (kl in 2:4){
  i <- kl-1
  file_base <- paste0("main_event_study_rural_acpop_", mods[i])
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(18:13, 19:24), c(  3, 4, 22:17, 23:28)  ]
  agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                    ylim_ori = c(-80, 50), ylim_rot = c(-80, 50),
                    xlab = "Time from Treatment (months)", 
                    ylab = "Effect on Number of Fires (in 1,000 units)",
                    omitted_period = 0, honest = TRUE, 
                    extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                    extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
}



# Event studies of the politicians
df <- fread(file.path(table_farms, "_app_16_polischar_fe12_evst_all_rural_acpop.csv"))
kl <- 1
file_base <- paste0("_app_16_polischar_fe12_evst_all_rural_acpop_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(13:21), c(  3, 4, 17:25)  ]
agregation_result(ev, numPrePeriods=5, numPostPeriods = 5, M = 1, 
                  omitted_period = -1, honest = TRUE, 
                  ylim_ori = c(-20, 50), 
                  extra_args_relativeMagnitudes = list(l_vec=rep(1/5,5)),         
                  extra_args_sensitivityResults = list(l_vec=rep(1/5,5)))
mods <- c('downup', 'riceA', 'riceHA', 'riceP')
for (kl in 2:5){
  i <- kl-1
  file_base <- paste0("_app_16_polischar_fe12_evst_all_rural_acpop_", mods[i], "_", kl)
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(33:41), c(  3, 4, 37:45)  ]
  agregation_result(ev, numPrePeriods=5, numPostPeriods = 5, M = 1, 
                    omitted_period = -1, honest = TRUE, 
                    extra_args_relativeMagnitudes = list(l_vec=rep(1/5,5)),         
                    extra_args_sensitivityResults = list(l_vec=rep(1/5,5)))
}


# Event studies of the Protests
df <- fread(file.path(table_farms, "_app_17_5km_fe12_evst_all_rural_acpop.csv"))
kl <- 1
file_base <- paste0("_app_17_5km_fe12_evst_all_rural_acpop_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(13:21), c(  3, 4, 17:25)  ]
agregation_result(ev, numPrePeriods=8, numPostPeriods = 2, M = 1, 
                  omitted_period = -1, honest = TRUE,
                  extra_args_relativeMagnitudes = list(l_vec=rep(1/2,2)),         
                  extra_args_sensitivityResults = list(l_vec=rep(1/2,2)))
mods <- c('downup', 'riceA', 'riceHA', 'riceP')
for (kl in 2:5){
  i <- kl-1
  file_base <- paste0("_app_17_5km_fe12_evst_all_rural_acpop_", mods[i], "_", kl)
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(33:41), c(  3, 4, 37:45)  ]
  agregation_result(ev, numPrePeriods=8, numPostPeriods = 2, M = 1, 
                    omitted_period = -1, honest = TRUE,
                    extra_args_relativeMagnitudes = list(l_vec=rep(1/2,2)),         
                    extra_args_sensitivityResults = list(l_vec=rep(1/2,2)))
}


################################################################################




################################################################################
##################### Panel View Politicians Charac. ###########################

main_path <- "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
out_path <- file.path(main_path, "tex/paper/figures/panelview_self_profession.png")

df <- fread(file.path(main_path, "data_output/intermediate/0_master_merge_data_gen.csv"),
            select = c("unique_small_grid_id",  "monthyear", "self_profession", "count"))
df[is.na(self_profession), self_profession := 0]

png(
  filename = out_path,
  width    = 12,
  height   = 6,
  units    = "in",
  res      = 120
)

p <- panelview(
  count ~ self_profession,
  data         = df,
  D            = "self_profession",
  index        = c("unique_small_grid_id", "monthyear"),
  type         = "treat",
  by.timing    = TRUE,
  display.all  = TRUE,
  axis.lab.gap = c(5, 50),
  legend.labs  = c("Non-Agricultural Profession", "Self Agricultural Profession"),
  background   = "white",
  xlab         = "Month",
  ylab         = "",                    # remove y-axis label
  main         = ""
)

# Increase font sizes via ggplot2 theme overlay
library(ggplot2)
p <- p + theme(
  axis.title.x = element_text(size = 18),
  axis.text.x  = element_text(size = 14),
  legend.title = element_text(size = 16),
  legend.text  = element_text(size = 16),
  axis.text.y  = element_blank(),       # also drops y-tick labels for a clean axis
  axis.ticks.y = element_blank()
)

print(p)

dev.off()




# Stacked dataset
# Inspecting the images event studies
df <- fread(file.path(table_farms, "stacked_event_study_rural.csv"))
kl <- 1
file_base <- paste0("stacked_event_study_rural_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(16:27),  c(  3, 4, 20:31)  ]
agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                  xlab = "Time from Treatment (months)", 
                  ylab = "Effect on Number of Fires (in 1,000 units)",
                  omitted_period = 0, honest = TRUE, 
                  ylim_ori = c(-40, 20), ylim_rot = c(-40, 30),
                  extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                  extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
mods <- c( 'riceP')
for (kl in 2:2){
  i <- kl-1
  file_base <- paste0("main_event_study_rural_", mods[i])
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(42:53), c(  3, 4, 46:57)  ]
  agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                    ylim_ori = c(-80, 50), ylim_rot = c(-80, 50),
                    xlab = "Time from Treatment (months)", 
                    ylab = "Effect on Number of Fires (in 1,000 units)",
                    omitted_period = 0, honest = TRUE, 
                    extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                    extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
}





# Stacked dataset balanced panel
# Inspecting the images event studies
df <- fread(file.path(table_farms, "stacked_event_study_balanced_rural.csv"))
kl <- 1
file_base <- paste0("stacked_event_study_balanced_rural_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(16:27),  c(  3, 4, 20:31)  ]
agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                  xlab = "Time from Treatment (months)", 
                  ylab = "Effect on Number of Fires (in 1,000 units)",
                  omitted_period = 0, honest = TRUE, 
                  ylim_ori = c(-40, 20), ylim_rot = c(-40, 30),
                  extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                  extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
mods <- c( 'riceP')
for (kl in 2:2){
  i <- kl-1
  file_base <- paste0("stacked_event_study_balanced_rural_", mods[i])
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(42:53), c(  3, 4, 46:57)  ]
  agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                    ylim_ori = c(-80, 50), ylim_rot = c(-80, 50),
                    xlab = "Time from Treatment (months)", 
                    ylab = "Effect on Number of Fires (in 1,000 units)",
                    omitted_period = 0, honest = TRUE, 
                    extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                    extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
}








# Stacked dataset wiht downup based on ac population
# Inspecting the images event studies
df <- fread(file.path(table_farms, "stacked_event_study_pop_rural.csv"))
kl <- 1
file_base <- paste0("stacked_event_study_pop_rural_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(16:27),  c(  3, 4, 20:31)  ]
agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                  xlab = "Time from Treatment (months)", 
                  ylab = "Effect on Number of Fires (in 1,000 units)",
                  omitted_period = 0, honest = TRUE, 
                  ylim_ori = c(-60, 20), ylim_rot = c(-40, 30),
                  extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                  extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
mods <- c( 'riceP')
for (kl in 2:2){
  i <- kl-1
  file_base <- paste0("stacked_event_study_pop_rural_", mods[i])
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(42:53), c(  3, 4, 46:57)  ]
  agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                    ylim_ori = c(-120, 50), ylim_rot = c(-100, 50),
                    xlab = "Time from Treatment (months)", 
                    ylab = "Effect on Number of Fires (in 1,000 units)",
                    omitted_period = 0, honest = TRUE, 
                    extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                    extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
}





# Stacked dataset balanced panel
# Inspecting the images event studies
df <- fread(file.path(table_farms, "stacked_event_study_balanced_pop_rural.csv"))
kl <- 1
file_base <- paste0("stacked_event_study_balanced_pop_rural_", kl)
filterval <- paste0("evreg", kl)
ev <- df[reg == filterval,][c(16:27),  c(  3, 4, 20:31)  ]
agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                  xlab = "Time from Treatment (months)", 
                  ylab = "Effect on Number of Fires (in 1,000 units)",
                  omitted_period = 0, honest = TRUE, 
                  ylim_ori = c(-40, 20), ylim_rot = c(-40, 30),
                  extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                  extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
mods <- c( 'riceP')
for (kl in 2:2){
  i <- kl-1
  file_base <- paste0("stacked_event_study_balanced_pop_rural_", mods[i])
  filterval <- paste0("evreg", kl)
  ev <- df[reg == filterval,][c(42:53), c(  3, 4, 46:57)  ]
  agregation_result(ev, numPrePeriods=6, numPostPeriods = 6, M = 1, 
                    ylim_ori = c(-80, 50), ylim_rot = c(-80, 50),
                    xlab = "Time from Treatment (months)", 
                    ylab = "Effect on Number of Fires (in 1,000 units)",
                    omitted_period = 0, honest = TRUE, 
                    extra_args_relativeMagnitudes = list(l_vec=rep(1/6,6)),         
                    extra_args_sensitivityResults = list(l_vec=rep(1/6,6)))
}

################################################################################



################################################################################
########################## Panel View Protests #################################

main_path <- "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
out_path <- file.path(main_path, "tex/paper/figures/panelview_protests.png")

df <- fread(file.path(main_path, "data_output/intermediate/0_master_merge_data_gen.csv"),
            select = c("unique_small_grid_id", "year", "month", "monthyear", "count"))
protests <- fread(file.path(main_path, "data_output/intermediate/8_grids_ac_pr_5km.csv"))
protests$protest.treat <- 1
df <- merge(df, protests, by = 'unique_small_grid_id', all.x = TRUE )
df[is.na(protest.treat), protest.treat := 0]
df[, protest.post := fifelse(
  !is.na(yr_pr_5km) & (year * 100 + month) > (yr_pr_5km * 100 + mt_pr_5km),
  1L, 0L
)]
df$protest.d <- df$protest.treat * df$protest.post

png(
  filename = out_path,
  width    = 12,
  height   = 6,
  units    = "in",
  res      = 120
)

p <- panelview(
  count ~ protest.d,
  data         = df,
  D            = "protest.d",
  index        = c("unique_small_grid_id", "monthyear"),
  type         = "treat",
  by.timing    = TRUE,
  display.all  = TRUE,
  axis.lab.gap = c(5, 50),
  legend.labs  = c("No Protest", "Protest 5km"),
  background   = "white",
  xlab         = "Month",
  ylab         = "",                    # remove y-axis label
  main         = ""
)

# Increase font sizes via ggplot2 theme overlay
library(ggplot2)
p <- p + theme(
  axis.title.x = element_text(size = 18),
  axis.text.x  = element_text(size = 14),
  legend.title = element_text(size = 16),
  legend.text  = element_text(size = 16),
  axis.text.y  = element_blank(),       # also drops y-tick labels for a clean axis
  axis.ticks.y = element_blank()
)

print(p)

dev.off()

################################################################################
