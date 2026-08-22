param(
    [string]$RepositoryRoot = "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms",
    [string]$DataRoot = "C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms",
    [string]$RscriptCommand = "Rscript"
)

$ErrorActionPreference = "Stop"
$plotScript = Join-Path $RepositoryRoot "code\_stacked_downup_replication\plotting_event_studies.R"
$tablesPath = Join-Path $RepositoryRoot "tables"

if (-not (Test-Path -LiteralPath $plotScript)) {
    throw "Plotting script not found: $plotScript"
}
if (-not (Test-Path -LiteralPath $tablesPath)) {
    throw "Local tables folder not found: $tablesPath"
}

$requiredControlCsv = @(
    "_app_16_polischar_fe12_evst_all_rural_controls_both.csv",
    "_app_16_polischar_fe12_evst_all_rural_acpop_controls_both.csv",
    "_app_17_5km_fe12_evst_all_rural_controls_never.csv",
    "_app_17_5km_fe12_evst_all_rural_controls_both.csv",
    "_app_17_5km_fe12_evst_all_rural_controls_notyet.csv",
    "_app_17_5km_fe12_evst_all_rural_acpop_controls_never.csv",
    "_app_17_5km_fe12_evst_all_rural_acpop_controls_both.csv",
    "_app_17_5km_fe12_evst_all_rural_acpop_controls_notyet.csv"
)
$missingControlCsv = @(
    $requiredControlCsv | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $tablesPath $_))
    }
)
if ($missingControlCsv.Count -gt 0) {
    Write-Warning "Missing control-sample CSV files. Available event-study figures will still be generated. To generate the omitted control-sample figures, copy the corresponding ster files locally and rerun _run_local_ster_postprocessing.do:`n$($missingControlCsv -join "`n")"
}

& $RscriptCommand $plotScript `
    --root $DataRoot `
    --output-root $RepositoryRoot

if ($LASTEXITCODE -ne 0) {
    throw "plotting_event_studies.R failed with exit code $LASTEXITCODE"
}

Write-Host "Local event-study figures completed: $(Join-Path $RepositoryRoot 'figures')"
