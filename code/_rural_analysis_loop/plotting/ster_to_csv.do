*-------------------------------------------------------------------------------
* ster_to_csv.do
* Read a .ster produced by the rural analysis dofiles, restore every
* stored estimate, and export to a CSV usable by plotting_event_studies.R.
*
* Expected globals (set by the orchestrator before calling `do`):
*   $ster_path  : absolute path to the input .ster
*   $csv_path   : absolute path to the output .csv (basename used for _scalars.csv)
*   $plot_dir   : absolute path to this plotting folder (for estsave_csv.ado)
*-------------------------------------------------------------------------------

clear all
set more off

if "$ster_path" == "" | "$csv_path" == "" | "$plot_dir" == "" {
    display as error "ster_to_csv: missing required global(s). Need \$ster_path, \$csv_path, \$plot_dir."
    exit 198
}

qui do "${plot_dir}/tools/estsave_csv.ado"

display "Reading estimates from: ${ster_path}"
estread using "${ster_path}"

* Collect every evreg* that was successfully restored
local estlist ""
forvalues k = 1/200 {
    capture est dir evreg`k'
    if _rc == 0 local estlist "`estlist' evreg`k'"
}

if "`estlist'" == "" {
    display as error "ster_to_csv: no evreg* estimates found in ${ster_path}"
    exit 198
}

display "Exporting estimates:`estlist'"
estsave_csv `estlist' using "${csv_path}", replace

display "Wrote: ${csv_path}"
