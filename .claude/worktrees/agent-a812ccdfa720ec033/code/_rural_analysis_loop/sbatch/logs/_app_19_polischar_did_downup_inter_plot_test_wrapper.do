clear all
set more off
global location     "dbox"
global sample       "_sample"
global is_rural_var "is_rural_area"
global fe_list      "1 8 16 24 32"
global ster_suffix  "_test"
global shell        "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
global dbox         "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
global root         "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
qui do "${root}/code/_replication_rural/estsave_csv.ado"
do "/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/_rural_analysis_loop/_app_19_polischar_did_downup_inter_plot.do"
