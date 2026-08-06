********************************************************************************
* Plot neighbour-border estimates used by main.tex
********************************************************************************

if "$root" == "" {
    clear all
    set more off
    global location     "dbox"
    global sample       ""
    global is_rural_var "is_rural"
    global fe_list      "1"
    global ster_suffix  ""
    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"
    if "$location" == "dbox" {
        global root "$dbox"
    }
    else {
        global root "$shell"
    }
}

global tables  "${code}/../../tables"
global figures "${code}/../../figures"

est clear
estread using "${tables}/main_figure4_neighbour${sample}_rural${ster_suffix}.ster"
est restore reg1

tempfile plotdata controls
clear
set obs 1
forvalues q = 1/4 {
    gen point`q' = _b[`q'.dist_q#1.downwind_neighbours]
    gen lo`q' = point`q' - 1.96 * _se[`q'.dist_q#1.downwind_neighbours]
    gen hi`q' = point`q' + 1.96 * _se[`q'.dist_q#1.downwind_neighbours]
    gen cpoint`q' = _b[`q'.dist_q]
    gen clo`q' = cpoint`q' - 1.96 * _se[`q'.dist_q]
    gen chi`q' = cpoint`q' + 1.96 * _se[`q'.dist_q]
}
save `plotdata'

keep cpoint* clo* chi*
rename (cpoint1 clo1 chi1 cpoint2 clo2 chi2 cpoint3 clo3 chi3 cpoint4 clo4 chi4) ///
       (point1  lo1  hi1  point2  lo2  hi2  point3  lo3  hi3  point4  lo4  hi4)
gen series = 2
save `controls'

use `plotdata', clear
keep point* lo* hi*
gen series = 1
append using `controls'
gen point5 = 0
gen lo5 = 0
gen hi5 = 0
reshape long point lo hi, i(series) j(order)

set scheme plotplainblind
twoway ///
    (rarea lo hi order if series == 1, color(red%10)) ///
    (connect point order if series == 1, msymbol(S) color(red)) ///
    (rarea lo hi order if series == 2, color(blue%10)) ///
    (connect point order if series == 2, msymbol(T) color(blue)), ///
    xtitle("Distance from Assembly border segment g (quintiles)") ///
    ytitle("Effect on number of fires (x 1,000 units)") ///
    yline(0, lpattern(dash)) xlabel(1 "Closest" 5 "Farthest") legend(off)

graph export "${figures}/neighbor_output.pdf", replace as(pdf)

********************************************************************************
