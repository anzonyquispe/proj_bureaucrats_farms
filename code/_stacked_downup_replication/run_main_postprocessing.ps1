param(
    [ValidateSet("full", "sample")]
    [string]$DataSize = "full",

    [ValidateSet("all", "rice_high")]
    [string]$AnalysisSubsample = "all",

    [string]$RepositoryRoot = "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms",
    [string]$DataRoot = "C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms",
    [string]$StataExecutable = "C:\Program Files\Stata18\StataMP-64.exe",
    [string]$RscriptExecutable = "C:\Program Files\R\R-4.5.0\bin\Rscript.exe",

    [ValidateRange(5, 10)]
    [int]$MaxCores = 10,

    # HonestDiD is a production output. Retain IncludeHonestDiD for backwards
    # compatibility; use SkipHonestDiD only for a quick plotting smoke test.
    [switch]$IncludeHonestDiD,
    [switch]$SkipHonestDiD
)

$ErrorActionPreference = "Stop"
$sample = if ($DataSize -eq "sample") { "_sample" } else { "" }
$suffix = if ($AnalysisSubsample -eq "rice_high") { "_rice_high" } else { "" }
$generateHonestDiD = -not $SkipHonestDiD
if ($IncludeHonestDiD) { $generateHonestDiD = $true }
$code = Join-Path $RepositoryRoot "code\_stacked_downup_replication"
$bridge = Join-Path $code "_run_local_main_postprocessing.do"
$plotScript = Join-Path $code "plotting_event_studies.R"
$logDir = Join-Path $code "logs"

foreach ($required in @($StataExecutable, $RscriptExecutable, $bridge, $plotScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required local program or file is missing: $required"
    }
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$env:FARMS_LOCAL_REPO = $RepositoryRoot -replace '\\', '/'
$env:FARMS_LOCAL_DATA_ROOT = $DataRoot -replace '\\', '/'
$env:FARMS_LOCAL_SAMPLE = if ($sample) { $sample } else { "none" }
$env:FARMS_LOCAL_SUFFIX = if ($suffix) { $suffix } else { "none" }

function Invoke-StataStage {
    param([ValidateSet("export", "tables")][string]$Stage, [switch]$Wait)
    $env:FARMS_LOCAL_STAGE = $Stage
    $automaticLog = Join-Path $logDir "_run_local_main_postprocessing.log"
    Remove-Item -LiteralPath $automaticLog -Force -ErrorAction SilentlyContinue
    $arguments = @("/e", "do", ('"{0}"' -f $bridge))
    $parameters = @{
        FilePath = $StataExecutable
        ArgumentList = $arguments
        WorkingDirectory = $logDir
        PassThru = $true
        WindowStyle = "Hidden"
    }
    $process = Start-Process @parameters
    if ($Wait) {
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Stata $Stage stage failed with exit code $($process.ExitCode)."
        }
        $stataLog = Join-Path $logDir "local_main_${Stage}${sample}${suffix}.stata.log"
        if (-not (Test-Path -LiteralPath $stataLog)) {
            throw "Stata did not create its expected log: $stataLog"
        }
        if (Select-String -LiteralPath $stataLog -Pattern '^r\([1-9][0-9]*\);\s*$' -Quiet) {
            throw "Stata $Stage stage contains an uncaught error. Inspect $stataLog"
        }
        Remove-Item -LiteralPath $automaticLog -Force -ErrorAction SilentlyContinue
    }
    return $process
}

Write-Host "Stage 1/2: exporting production event-study CSV files."
Invoke-StataStage -Stage export -Wait | Out-Null

$plotJobs = @(
    @{ Name = "downup_area"; Families = "main"; Cases = "final_stacked_area_baseline" },
    @{ Name = "downup_pop"; Families = "main"; Cases = "final_stacked_population_baseline" },
    @{ Name = "politician"; Families = "main"; Cases = "final_politician_fe03_baseline" },
    @{ Name = "protest"; Families = "protest"; Cases = "" }
)

# With HonestDiD, divide at most nine R workers across the four plot jobs and
# reserve one core for Stata table generation. Without HonestDiD the four R
# processes are independent but ordinary ggplot rendering is single-threaded.
$rBudget = [Math]::Max(1, $MaxCores - 1)
$baseHonestCores = [Math]::Max(1, [Math]::Floor($rBudget / $plotJobs.Count))
$extraCores = $rBudget - ($baseHonestCores * $plotJobs.Count)

Write-Host "Stage 2/2: generating tables and four main plot families concurrently."
$tableProcess = Invoke-StataStage -Stage tables
$processes = @(@{ Name = "tables"; Process = $tableProcess; Log = (Join-Path $logDir "local_main_tables${sample}${suffix}.stata.log") })

for ($index = 0; $index -lt $plotJobs.Count; $index++) {
    $job = $plotJobs[$index]
    $honestCores = $baseHonestCores + $(if ($index -lt $extraCores) { 1 } else { 0 })
    $arguments = @(
        $plotScript,
        "--root", $DataRoot,
        "--output-root", $RepositoryRoot,
        "--sample", $(if ($sample) { $sample } else { "none" }),
        "--suffix", $(if ($suffix) { $suffix } else { "none" }),
        "--families", $job.Families
    )
    if ($job.Cases) { $arguments += @("--cases", $job.Cases) }
    if ($generateHonestDiD) {
        $arguments += @("--honest", "--honest-cores", $honestCores)
    }
    else {
        $arguments += "--skip-honest"
    }

    $stdout = Join-Path $logDir ("local_plot_{0}{1}{2}.stdout.tmp" -f $job.Name, $sample, $suffix)
    $stderr = Join-Path $logDir ("local_plot_{0}{1}{2}.stderr.tmp" -f $job.Name, $sample, $suffix)
    $log = Join-Path $logDir ("local_plot_{0}{1}{2}.log" -f $job.Name, $sample, $suffix)
    $process = Start-Process -FilePath $RscriptExecutable -ArgumentList $arguments `
        -WorkingDirectory $RepositoryRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $processes += @{
        Name = $job.Name; Process = $process; Log = $log;
        Stdout = $stdout; Stderr = $stderr
    }
}

$failures = @()
foreach ($item in $processes) {
    $item.Process.WaitForExit()
    if ($item.ContainsKey("Stdout")) {
        $content = @()
        if (Test-Path -LiteralPath $item.Stdout) { $content += Get-Content -LiteralPath $item.Stdout }
        if (Test-Path -LiteralPath $item.Stderr) { $content += Get-Content -LiteralPath $item.Stderr }
        Set-Content -LiteralPath $item.Log -Value $content
        Remove-Item -LiteralPath $item.Stdout, $item.Stderr -Force -ErrorAction SilentlyContinue
    }
    if ($item.Process.ExitCode -ne 0) {
        $failures += "$($item.Name) (exit $($item.Process.ExitCode)); log: $($item.Log)"
    }
}

$tableLog = Join-Path $logDir "local_main_tables${sample}${suffix}.stata.log"
if (Test-Path -LiteralPath $tableLog) {
    if (Select-String -LiteralPath $tableLog -Pattern '^r\([1-9][0-9]*\);\s*$' -Quiet) {
        $failures += "tables (uncaught Stata error); log: $tableLog"
    }
}
else {
    $failures += "tables (missing Stata log): $tableLog"
}
Remove-Item -LiteralPath (Join-Path $logDir "_run_local_main_postprocessing.log") `
    -Force -ErrorAction SilentlyContinue

if ($failures.Count) {
    throw "Local post-processing failed:`n$($failures -join "`n")"
}

Write-Host "Completed tables and main event-study figures."
Write-Host "Sample=$DataSize; analysis subsample=$AnalysisSubsample; maximum cores=$MaxCores"
Write-Host "HonestDiD=$generateHonestDiD; event-study families=$($plotJobs.Count)"
Write-Host "Outputs: $(Join-Path $RepositoryRoot 'tables') and $(Join-Path $RepositoryRoot 'figures')"
