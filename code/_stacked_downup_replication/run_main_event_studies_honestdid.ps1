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

Write-Host "Stage 2/2: plotting event studies and HonestDiD with 10 total workers."
$common = @(
    $plotter, "--root", $DataRoot, "--output-root", $RepositoryRoot,
    "--sample", "none", "--suffix", "none", "--honest",
    "--honest-cores", "5"
)

$jobs = @(
    @{
        Name = "downup";
        Args = $common + @(
            "--families", "main", "--cases",
            "final_stacked_area_baseline,final_stacked_area_rice,final_stacked_population_baseline,final_stacked_population_rice"
        )
    },
    @{
        Name = "politician_protest";
        Args = $common + @(
            "--families", "main,protest", "--cases",
            "final_politician_fe03_baseline,final_politician_fe03_rice"
        )
    }
)

$running = foreach ($job in $jobs) {
    $stdout = Join-Path $logDir "local_event_honest_$($job.Name).stdout.log"
    $stderr = Join-Path $logDir "local_event_honest_$($job.Name).stderr.log"
    $process = Start-Process -FilePath $RscriptExecutable `
        -ArgumentList $job.Args -WorkingDirectory $RepositoryRoot `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr
    [pscustomobject]@{ Name=$job.Name; Process=$process; Stdout=$stdout; Stderr=$stderr }
}

$failures = @()
foreach ($job in $running) {
    $job.Process.WaitForExit()
    $job.Process.Refresh()
    $content = @()
    if (Test-Path $job.Stdout) { $content += Get-Content $job.Stdout }
    if (Test-Path $job.Stderr) { $content += Get-Content $job.Stderr }
    $finalLog = Join-Path $logDir "local_event_honest_$($job.Name).log"
    Set-Content -LiteralPath $finalLog -Value $content
    Remove-Item $job.Stdout,$job.Stderr -Force -ErrorAction SilentlyContinue
    if (-not (Select-String -LiteralPath $finalLog `
            -Pattern '^All requested event-study and HonestDiD plots completed\.$' -Quiet)) {
        $failures += "$($job.Name): $finalLog"
    }
}

if ($failures.Count) {
    throw "Event-study/HonestDiD plotting failed:`n$($failures -join "`n")"
}
Write-Host "Completed all main event-study, rotated, and HonestDiD figures."
Write-Host "Outputs: $(Join-Path $RepositoryRoot 'figures')"
