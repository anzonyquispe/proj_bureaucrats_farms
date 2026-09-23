param(
    [string]$RepositoryRoot = "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms",
    [string]$DataRoot = "C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms",
    [string]$StataExecutable = "C:\Program Files\Stata18\StataMP-64.exe",
    [string]$RscriptExecutable = "C:\Program Files\R\R-4.5.0\bin\Rscript.exe"
)

$ErrorActionPreference = "Stop"
$code = Join-Path $RepositoryRoot "code\_stacked_downup_replication"
$bridge = Join-Path $code "_run_local_main_postprocessing.do"
$plotter = Join-Path $code "plotting_event_studies.R"
$logDir = Join-Path $code "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

foreach ($required in @($StataExecutable, $RscriptExecutable, $bridge, $plotter)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required file or program: $required"
    }
}

# Re-export the updated production .ster files before plotting.
$env:FARMS_LOCAL_REPO = $RepositoryRoot -replace '\\', '/'
$env:FARMS_LOCAL_DATA_ROOT = $DataRoot -replace '\\', '/'
$env:FARMS_LOCAL_SAMPLE = "none"
$env:FARMS_LOCAL_SUFFIX = "none"
$env:FARMS_LOCAL_STAGE = "export"

Write-Host "Stage 1/2: exporting updated event-study STER files to CSV."
$stata = Start-Process -FilePath $StataExecutable `
    -ArgumentList @("/e", "do", ('"{0}"' -f $bridge)) `
    -WorkingDirectory $logDir -WindowStyle Hidden -PassThru -Wait
$exportLog = Join-Path $logDir "local_main_export.stata.log"
if (-not (Test-Path -LiteralPath $exportLog)) {
    throw "Missing Stata export log: $exportLog"
}
if (Select-String -LiteralPath $exportLog -Pattern '^r\([1-9][0-9]*\);\s*$' -Quiet) {
    throw "Event-study export failed. Inspect $exportLog"
}

Write-Host "Stage 2/2: plotting event studies and both HonestDiD methods with 10 total workers."
$arguments = @(
    $plotter, "--root", $DataRoot, "--output-root", $RepositoryRoot,
    "--sample", "none", "--suffix", "none", "--honest",
    "--honest-cores", "10", "--families", "main,protest", "--cases",
    "final_stacked_area_baseline,final_stacked_area_rice,final_stacked_population_baseline,final_stacked_population_rice,final_politician_fe03_baseline,final_politician_fe03_rice"
)

$stdout = Join-Path $logDir "local_event_honest_main.stdout.log"
$stderr = Join-Path $logDir "local_event_honest_main.stderr.log"
$finalLog = Join-Path $logDir "local_event_honest_main.log"
$process = Start-Process -FilePath $RscriptExecutable `
    -ArgumentList $arguments -WorkingDirectory $RepositoryRoot `
    -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr
$content = @()
if (Test-Path $stdout) { $content += Get-Content $stdout }
if (Test-Path $stderr) { $content += Get-Content $stderr }
Set-Content -LiteralPath $finalLog -Value $content
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
if (-not (Select-String -LiteralPath $finalLog `
        -Pattern '^All requested event-study and HonestDiD plots completed\.$' -Quiet)) {
    throw "Event-study/HonestDiD plotting failed. Inspect $finalLog"
}
Write-Host "Completed all main event-study, rotated, HonestDiD relative-magnitudes, and HonestDiD smoothness figures."
Write-Host "Outputs: $(Join-Path $RepositoryRoot 'figures')"
