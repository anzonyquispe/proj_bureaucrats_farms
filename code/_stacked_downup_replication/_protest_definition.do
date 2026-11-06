********************************************************************************
* Select the protest definition from $stacked_file before loading the protest
* stack. Every protest dofile includes this file.
*
* $stacked_file == "stacked_data_protest2_5km": Gemini-classified protests
*   (farmer_led or solidarity). Reads stacked_data_protest2_5km_election_sameterm,
*   clusters on grid_month_ac_area_tr_protest2 and appends _protest2 to
*   $ster_suffix, so a protest2 run never overwrites a keyword-rule output.
* Any other value: the keyword-rule protests used in the paper.
*
* Sets $protest_input, $protest_clusters and $protest_tag.
********************************************************************************

local intermediate "${root}/data_output/intermediate"
local stack "stacked_data_protest5km"
global protest_tag ""
if "$stacked_file" == "stacked_data_protest2_5km" {
    local stack "$stacked_file"
    global protest_tag "_protest2"
    if strpos("${ster_suffix}", "${protest_tag}") == 0 {
        global ster_suffix "${ster_suffix}${protest_tag}"
    }
}

global protest_input "`intermediate'/`stack'_election_sameterm${sample}.csv"
foreach dir in cohortes_protest_term cohorts_protest_term {
    capture confirm file "${protest_input}"
    if _rc global protest_input "`intermediate'/`dir'/`stack'_election_sameterm${sample}.csv"
}
confirm file "${protest_input}"
global protest_clusters "`intermediate'/grid_month_ac_area_tr${protest_tag}.dta"

display as result "Protest stack: ${protest_input}"
display as result "Protest clusters: ${protest_clusters}"
display as result "Output suffix: ${ster_suffix}"
