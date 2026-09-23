$ErrorActionPreference = "Stop"

$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Rscript = "C:\Program Files\R\R-4.5.0\bin\Rscript.exe"
$PdfLaTeX = "C:\Users\eunic\AppData\Local\Programs\MiKTeX\miktex\bin\x64\pdflatex.exe"

if (-not (Test-Path $Rscript)) { throw "Rscript not found: $Rscript" }
if (-not (Test-Path $PdfLaTeX)) { throw "pdflatex not found: $PdfLaTeX" }

$PolDir = Join-Path $Repo "code\_stacked_downup_replication\exploratory_analysis\politician_original_controls_fe_sweep"
$ProtestDir = Join-Path $Repo "code\_stacked_downup_replication\exploratory_analysis\protest_original_controls_fe_sweep"
$ReportDir = Join-Path $Repo "code\_report"

& $Rscript (Join-Path $PolDir "plot_politician_original_controls_fe_sweep.R") `
    --root $Repo --output-root $Repo
if ($LASTEXITCODE -ne 0) { throw "Politician plot generation failed." }

& $Rscript (Join-Path $PolDir "build_politician_original_controls_reports.R") `
    --root $Repo
if ($LASTEXITCODE -ne 0) { throw "Politician TeX generation failed." }

& $Rscript (Join-Path $ProtestDir "plot_protest_original_controls_fe_sweep.R") `
    --root $Repo --output-root $Repo
if ($LASTEXITCODE -ne 0) { throw "Protest plot generation failed." }

& $Rscript (Join-Path $ProtestDir "build_protest_original_controls_reports.R") `
    --root $Repo
if ($LASTEXITCODE -ne 0) { throw "Protest TeX generation failed." }

$TexFiles = @(
    "politician_original_controls_never_report.tex",
    "politician_original_controls_both_report.tex",
    "politician_original_controls_notyet_report.tex",
    "protest_original_controls_never_report.tex",
    "protest_original_controls_both_report.tex",
    "protest_original_controls_notyet_report.tex"
)
Push-Location $ReportDir
try {
    foreach ($TexFile in $TexFiles) {
        & $PdfLaTeX -interaction=nonstopmode -halt-on-error $TexFile
        if ($LASTEXITCODE -ne 0) { throw "First LaTeX pass failed: $TexFile" }
        & $PdfLaTeX -interaction=nonstopmode -halt-on-error $TexFile
        if ($LASTEXITCODE -ne 0) { throw "Second LaTeX pass failed: $TexFile" }
    }
}
finally {
    Pop-Location
}

Write-Host "Generated six TeX/PDF reports in $ReportDir"
