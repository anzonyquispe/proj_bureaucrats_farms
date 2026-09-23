********************************************************************************
* Alternative dependent variables using population-based Down > Up treatment.
* The historical output filename is retained for compatibility with main_v3.tex.
* Different dependent variables: Any Fire, Log Fires, Mean Brightness
********************************************************************************

********************************************************************************
* Setup - Only set globals if running standalone (not from master)
********************************************************************************

if "$root" == "" {
    clear all
    set more off

    global location "shell"
    global sample ""
    global is_rural_var "is_rural"
    global fe_list "1/3"
    global ster_suffix ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}

cd "${root}"
global int_farms "${root}/data_output/intermediate"
global table_farms "${code}/../../tables"
global figure_farms "${code}/../../figures"
********************************************************************************
* Import Data
********************************************************************************

* Use exactly the specification-4 population sample from the main DiD.
import delimited ///
    "${root}/data_output/intermediate/main_downup_ac_pop_esample${sample}.csv", ///
    clear varnames(1)
local common_n = _N
display as text "Loaded canonical main specification-4 sample: `common_n' rows"

* Create count in thousands
capture drop countk
gen countk = count * 1000

********************************************************************************
* Create dependent variables
********************************************************************************

* Any fire (binary)
gen anyfire = (countk > 0)

* Log fires
gen logfire = ln(count + 1)

* Mean brightness - replace missing with 0
replace mean_brightness = 0 if missing(mean_brightness)

********************************************************************************
* Encode IDs
********************************************************************************

capture drop grid_id ac_id
capture confirm numeric variable unique_small_grid_id
if _rc {
    encode unique_small_grid_id, gen(grid_id)
}
else {
    gen grid_id = unique_small_grid_id
}

capture confirm numeric variable ac_uq_id
if _rc {
    encode ac_uq_id, gen(ac_id)
}
else {
    gen ac_id = ac_uq_id
}



egen tag_ac = tag(ac_id)
count if tag_ac == 1
local numacs = r(N)

********************************************************************************
* Project-standard treated-group pre-treatment means for each dependent variable.
********************************************************************************
gen moderator = 0
quietly summarize anyfire if treat == 1 & relative_monthyear <= -1
local meandv1 = r(mean)
quietly summarize anyfire if treat == 1 & relative_monthyear <= -1 & moderator == 1
local meandv1_mod = r(mean)
quietly summarize logfire if treat == 1 & relative_monthyear <= -1
local meandv2 = r(mean)
quietly summarize logfire if treat == 1 & relative_monthyear <= -1 & moderator == 1
local meandv2_mod = r(mean)
quietly summarize mean_brightness if treat == 1 & relative_monthyear <= -1
local meandv3 = r(mean)
quietly summarize mean_brightness if treat == 1 & relative_monthyear <= -1 & moderator == 1
local meandv3_mod = r(mean)

********************************************************************************
* Run Regressions
********************************************************************************

* FE
global setfe grid_id#cohort ac_id#monthyear#cohort

* Controls
global controls av_wind_speed wind_direction

* Cluster variables
global cluster ac_uq_id#cohort#monthyear unique_small_grid_id#cohort



* Eq1: Any Fire
reghdfejl anyfire downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv1'
estadd scalar ymean2 = `meandv1_mod'
estadd scalar acq = `numacs'
est store eq1

* Eq2: Log Fires
reghdfejl logfire downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv2'
estadd scalar ymean2 = `meandv2_mod'
estadd scalar acq = `numacs'
est store eq2

* Eq3: Mean Brightness
reghdfejl mean_brightness downup_ac_pop $controls , ///
    absorb($setfe ) cluster($cluster )
assert e(N) == `common_n'
estadd local gridfe "Y"
estadd local acmonthfe "Y"
estadd scalar ymean = `meandv3'
estadd scalar ymean2 = `meandv3_mod'
estadd scalar acq = `numacs'
est store eq3

********************************************************************************
* Save ster file
********************************************************************************

estwrite eq* using ///
    "${code}/../../tables/_app_7_main_did_downup_area_ac_dv${sample}_rural_stacked${ster_suffix}.ster", replace

display "Ster: ${code}/../../tables/_app_7_main_did_downup_area_ac_dv${sample}_rural_stacked${ster_suffix}.ster"

********************************************************************************
* Write the canonical population-treatment LaTeX table in the same job.
********************************************************************************

esttab eq1 eq2 eq3 using ///
    "${code}/../../tables/_app_7_main_did_downup_area_ac_dv${sample}_rural_acpop${ster_suffix}.tex", ///
    replace ///
    cells(b(fmt(4) star) se(par fmt(4))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(downup_ac_pop) ///
    varlabels(downup_ac_pop "Down \$>\$ Up") ///
    stats(N acq gridfe acmonthfe ymean, ///
          fmt(%12.0fc %12.0fc %s %s %9.3fc) ///
          labels("Observations" "N Assembly Constituencies" ///
                 "Grid FE \$\times\$ Cohort" ///
                 "Assembly \$\times\$ Month-Year \$\times\$ Cohort FE" ///
                 "Mean DV")) ///
    nomtitles nonumbers collabels(none) nobaselevels ///
    prehead("\begin{tabular}{lccc}" ///
            "\tabularnewline \hline" ///
            "& (1) & (2) & (3)\\" ///
            "& Any Fire & Log (N) Fires & Mean Brightness\\" ///
            "\hline") ///
    posthead("") prefoot("\hline") ///
    postfoot("\hline" "\end{tabular}")

display as result "Generated population-treatment table: " ///
    "${code}/../../tables/_app_7_main_did_downup_area_ac_dv${sample}_rural_acpop${ster_suffix}.tex"

********************************************************************************
