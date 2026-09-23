$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$PlotScript = Join-Path $PSScriptRoot "plot_politician_byprov_fe_sweep.R"
$Candidates = @(
    "C:\Program Files\R\R-4.5.0\bin\Rscript.exe",
    "C:\Program Files\R\R-4.4.3\bin\Rscript.exe",
    "Rscript.exe"
)

$Rscript = $null
foreach ($Candidate in $Candidates) {
    if (Test-Path $Candidate) {
        $Rscript = $Candidate
        break
    }
    $Command = Get-Command $Candidate -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        $Rscript = $Command.Source
        break
    }
}
if ($null -eq $Rscript) {
    throw "Rscript was not found. Install R or add Rscript.exe to PATH."
}

& $Rscript $PlotScript --root $RepoRoot --output-root $RepoRoot
if ($LASTEXITCODE -ne 0) {
    throw "Politician FE plotting failed with exit code $LASTEXITCODE"
}

Write-Host "Plots: $RepoRoot\figures\exploratory_analysis\politician_byprov_fe_sweep"
Write-Host "Atlas: $RepoRoot\tables\exploratory_analysis\politician_byprov_fe_sweep"

