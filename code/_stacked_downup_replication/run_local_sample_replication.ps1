$ErrorActionPreference = "Stop"

$stata = "C:\Program Files\Stata18\StataMP-64.exe"
$repo = "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms"
$dofile = Join-Path $repo "code\_stacked_downup_replication\run_local_sample_replication.do"
$log = Join-Path $repo "code\_stacked_downup_replication\_master_replication_log_sample.txt"
$intermediate = "C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms\data_output\intermediate"

if (-not (Test-Path -LiteralPath $stata)) {
    throw "Stata executable not found: $stata"
}
if (-not (Test-Path -LiteralPath $dofile)) {
    throw "Sample replication dofile not found: $dofile"
}

$requiredInputs = @(
    "0_master_dataset_sample.csv",
    "combined_dt_sample.csv",
    "combined_dt_pop_sample.csv",
    "politicians_characteristics_byprov_sample.csv",
    "stacked_data_protest5km_election_sameterm_sample.csv",
    "stacked_downup_13kmpl_sample.csv",
    "stacked_downup_neigh_sample.csv",
    "ghs_grid_classification_2000.dta",
    "AC_total_pop.dta"
)
$missingInputs = @(
    $requiredInputs | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $intermediate $_))
    }
)
if ($missingInputs.Count -gt 0) {
    throw "Missing required local sample inputs:`n$($missingInputs -join "`n")"
}

Write-Host "Running all main analyses with *_sample inputs..."
$process = Start-Process -FilePath $stata `
    -ArgumentList "/e", "do", ('"' + $dofile + '"') `
    -WorkingDirectory $repo -Wait -PassThru

if ($process.ExitCode -ne 0) {
    throw "Stata failed with exit code $($process.ExitCode). Inspect: $log"
}
if (-not (Test-Path -LiteralPath $log)) {
    throw "Stata exited without creating the expected log: $log"
}

$failure = Select-String -Path $log -Pattern '^r\([1-9][0-9]*\);\s*$' | Select-Object -Last 1
if ($failure) {
    throw "Stata reported $($failure.Line). Inspect: $log"
}
if (-not (Select-String -Path $log -SimpleMatch "STATA REPLICATION COMPLETED" -Quiet)) {
    throw "The completion marker is absent. Inspect: $log"
}

Write-Host "Local sample replication completed successfully."
Write-Host "Log: $log"
