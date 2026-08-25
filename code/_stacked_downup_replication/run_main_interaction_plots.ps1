param(
    [ValidateSet("full", "sample")]
    [string]$DataSize = "full",

    [ValidateSet("all", "rice_high")]
    [string]$AnalysisSubsample = "all",

    [string]$RepositoryRoot = "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms",
    [string]$DataRoot = "C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms",
    [string]$StataExecutable = "C:\Program Files\Stata18\StataMP-64.exe"
)

$ErrorActionPreference = "Stop"
$sample = if ($DataSize -eq "sample") { "_sample" } else { "" }
$suffix = if ($AnalysisSubsample -eq "rice_high") { "_rice_high" } else { "" }
$code = Join-Path $RepositoryRoot "code\_stacked_downup_replication"
$bridge = Join-Path $code "_run_local_main_postprocessing.do"
$logDir = Join-Path $code "logs"
$stageLog = Join-Path $logDir "local_main_interactions${sample}${suffix}.stata.log"

foreach ($required in @($StataExecutable, $bridge)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required local program or file is missing: $required"
    }
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$env:FARMS_LOCAL_REPO = $RepositoryRoot -replace '\\', '/'
$env:FARMS_LOCAL_DATA_ROOT = $DataRoot -replace '\\', '/'
$env:FARMS_LOCAL_SAMPLE = if ($sample) { $sample } else { "none" }
$env:FARMS_LOCAL_SUFFIX = if ($suffix) { $suffix } else { "none" }
$env:FARMS_LOCAL_STAGE = "interactions"

Write-Host "Generating only the main interaction plots."
$process = Start-Process -FilePath $StataExecutable `
    -ArgumentList @("/e", "do", ('"{0}"' -f $bridge)) `
    -WorkingDirectory $logDir -WindowStyle Hidden -PassThru -Wait
$process.Refresh()

if (-not (Test-Path -LiteralPath $stageLog)) {
    throw "Stata did not create its expected log: $stageLog"
}
if (Select-String -LiteralPath $stageLog -Pattern '^r\([1-9][0-9]*\);\s*$' -Quiet) {
    throw "Interaction plotting contains an uncaught Stata error. Inspect $stageLog"
}
if (-not (Select-String -LiteralPath $stageLog `
        -Pattern '^LOCAL MAIN POST-PROCESSING STAGE COMPLETED: interactions$' -Quiet)) {
    throw "Interaction plotting did not reach its completion marker. Inspect $stageLog"
}

Write-Host "Completed main interaction plots."
Write-Host "Figures: $(Join-Path $RepositoryRoot 'figures')"
Write-Host "Log: $stageLog"
