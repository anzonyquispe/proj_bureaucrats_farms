********************************************************************************
* Shared configuration for the replication package
********************************************************************************

* The five globals below may be set by an sbatch wrapper before this file runs.
* This block supplies standalone defaults in one place only.
if "$root" == "" {
    if "$location" == ""     global location "shell"
    if "$sample" == ""       global sample ""
    if "$is_rural_var" == "" global is_rural_var "is_rural_area"
    if "$fe_list" == ""      global fe_list "1/3"
    if "$ster_suffix" == ""  global ster_suffix ""

    global shell "/groups/sgulzar/sa_fires/proj_bureaucrats_farms"
    global dbox  "/Users/anzony.quisperojas/Library/CloudStorage/Dropbox/sa_fires/proj_bureaucrats_farms"

    global code_shell "/users/aquisper/proj_bureaucrats_farms/code/replication_package"
    global code_dbox  "/Users/anzony.quisperojas/Documents/GitHub/proj_bureaucrats_farms/code/replication_package"

    if "$location" == "dbox" {
        global root "$dbox"
        global code "$code_dbox"
        global python "python"
    }
    else {
        global root "$shell"
        global code "$code_shell"
        global python "python3"
    }
}

* A caller that supplies $root may also supply $code. This fallback supports
* running from the package directory with an externally configured data root.
if "$code" == "" global code "code/replication_package"
if "$python" == "" global python "python3"

global int_data "${root}/data_output/intermediate"
global tables   "${root}/tex/paper/tables"
global figures  "${root}/tex/paper/figures"
global int_farms "${int_data}"
global table_farms "${tables}"
global figure_farms "${figures}"

capture mkdir "${root}/tex"
capture mkdir "${root}/tex/paper"
capture mkdir "${tables}"
capture mkdir "${figures}"
capture mkdir "${code}/logs"

********************************************************************************
