param(
    [string]$RepositoryRoot = "C:\Users\eunic\OneDrive\Documents\GitHub\proj_bureaucrats_farms",
    [string]$DataRoot = "C:\Users\eunic\Dropbox\sa_fires\proj_bureaucrats_farms",
    [string]$StataExecutable = "C:\Program Files\Stata18\StataMP-64.exe",
    [string]$RscriptExecutable = "C:\Program Files\R\R-4.5.0\bin\Rscript.exe",
    [ValidateRange(5, 10)]
    [int]$MaxCores = 10
)

$ErrorActionPreference = "Stop"
$code = Join-Path $RepositoryRoot "code\_stacked_downup_replication"
$tables = Join-Path $RepositoryRoot "tables"
$figures = Join-Path $RepositoryRoot "figures"
$report = Join-Path $RepositoryRoot "code\_report"
$postprocessor = Join-Path $code "run_main_postprocessing.ps1"
$renderer = Join-Path $report "render_main_abovemedian.cmd"

# These files are the minimum outputs needed for every above-median table,
# event study, HonestDiD result, and interaction figure. All must retain the
# _rice_high suffix so full-sample results can never be used accidentally.
$requiredSterFiles = @(
    "main_did_downup_area_ac_rural_stacked_rice_high.ster",
    "main_did_downup_pop_ac_rural_stacked_rice_high.ster",
    "_main_3_bureau_polisc_did_rural_stacked_rice_high.ster",
    "_main_4_protest_5km_fe12_did_downup_rural_rice_high.ster",
    "_main_4_protest_5km_fe12_did_downup_rural_acpop_rice_high.ster",
    "_main_5_polischar_fe12_did_downup_inter_rural_rice_high.ster",
    "_main_5_polischar_fe12_did_downup_inter_rural_acpop_rice_high.ster",
    "stacked_event_study_5pre_rural_rice_high.ster",
    "stacked_event_study_pop_5pre_rural_rice_high.ster",
    "_app_16_polischar_fe12_evst_all_rural_acpop_rice_high_controls_both.ster",
    "_app_17_5km_fe12_evst_all_rural_rice_high.ster",
    "_app_18_protest_5km_fe12_did_downup_plot_rural_rice_high.ster",
    "_app_18_protest_5km_fe12_did_downup_plot_rural_acpop_rice_high.ster",
    "_app_19_polischar_fe12_did_downup_inter_plot_rural_rice_high.ster",
    "_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop_rice_high.ster",
    "_app_6_main_did_treat_definition_rural_acpop_rice_high.ster",
    "_app_7_main_did_downup_area_ac_dv_rural_stacked_rice_high.ster",
    "_app_8_main_did_by_year_rural_stacked_rice_high.ster",
    "_app_9_main_did_by_state_rural_stacked_rice_high.ster",
    "_app_11_placebo_pop_13km_rural_rice_high.ster",
    "main_figure4_neighbour_rural_rice_high.ster"
)

$requiredClusterTables = @(
    "descriptives_main_rice_high.tex",
    "_protest_stacked_descriptive_rice_high.tex",
    "_politicians_stacked_descriptive_rice_high.tex"
)
$missingInputs = @()
foreach ($name in $requiredSterFiles + $requiredClusterTables) {
    $path = Join-Path $tables $name
    if (-not (Test-Path -LiteralPath $path)) { $missingInputs += $path }
}
if ($missingInputs.Count) {
    $message = "Above-median cluster outputs are missing from the repository tables folder:`n" +
        ($missingInputs -join "`n") +
        "`nCopy or pull these files locally, then rerun this script."
    throw $message
}

Write-Host "Generating above-median tables, event studies, HonestDiD, and interactions."
& $postprocessor `
    -DataSize full `
    -AnalysisSubsample rice_high `
    -RepositoryRoot $RepositoryRoot `
    -DataRoot $DataRoot `
    -StataExecutable $StataExecutable `
    -RscriptExecutable $RscriptExecutable `
    -MaxCores $MaxCores

$expectedFigures = @(
    "stacked_event_study_5pre_rural_1_ori_rice_high.png",
    "stacked_event_study_5pre_rural_1_rotated_rice_high.png",
    "stacked_event_study_5pre_rural_1_honest2_rice_high.png",
    "stacked_event_study_5pre_rural_1_rot_honest2_rice_high.png",
    "stacked_event_study_pop_5pre_rural_1_ori_rice_high.png",
    "stacked_event_study_pop_5pre_rural_1_rotated_rice_high.png",
    "stacked_event_study_pop_5pre_rural_1_honest2_rice_high.png",
    "stacked_event_study_pop_5pre_rural_1_rot_honest2_rice_high.png",
    "_app_16_polischar_fe03_evst_main_rural_acpop_1_ori_rice_high.png",
    "_app_16_polischar_fe03_evst_main_rural_acpop_1_rotated_rice_high.png",
    "_app_16_polischar_fe03_evst_main_rural_acpop_1_honest2_rice_high.png",
    "_app_16_polischar_fe03_evst_main_rural_acpop_1_rot_honest2_rice_high.png",
    "_app_17_5km_fe12_evst_all_rural_fe03_1_ori_rice_high.png",
    "_app_17_5km_fe12_evst_all_rural_fe03_1_rotated_rice_high.png",
    "_app_17_5km_fe12_evst_all_rural_fe03_1_honest2_rice_high.png",
    "_app_17_5km_fe12_evst_all_rural_fe03_1_rot_honest2_rice_high.png",
    "_app_18_protest_5km_fe12_did_downup_plot_rural_acpop_rice_high.png",
    "_app_19_polischar_fe12_did_downup_inter_plot_rural_acpop_rice_high.png",
    "neighbor_output_rice_high.pdf"
)
$missingFigures = $expectedFigures | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $figures $_))
}
if ($missingFigures.Count) {
    throw "Above-median post-processing did not generate:`n$($missingFigures -join "`n")"
}

$expectedTables = @(
    "main_did_downup_area_ac_rural_rice_high.tex",
    "main_did_downup_ac_rural_acpop_rice_high.tex",
    "_main_3_bureau_polisc_did_rural_acpop_rice_high.tex",
    "_main_4_protest_5km_fe12_did_downup_rural_rice_high.tex",
    "_main_4_protest_5km_fe12_did_downup_rural_acpop_new_rice_high.tex",
    "_main_5_polischar_fe12_did_downup_inter_rural_rice_high.tex",
    "_main_5_polischar_fe12_did_downup_inter_rural_acpop_rice_high.tex",
    "_app_6_main_did_treat_definition_rural_acpop_new3_rice_high.tex",
    "_app_7_main_did_downup_area_ac_dv_rural_acpop_rice_high.tex",
    "_app_8_main_did_by_year_rural_acpop_rice_high.tex",
    "_app_9_main_did_by_state_rural_acpop_rice_high.tex",
    "_app_11_placebo_pop_13km_rural_rice_high.tex"
)
$missingTables = $expectedTables | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $tables $_))
}
if ($missingTables.Count) {
    throw "Above-median table generation did not produce:`n$($missingTables -join "`n")"
}

Write-Host "Rendering main_v3_abovemedian.pdf."
& $renderer
if ($LASTEXITCODE -ne 0) {
    throw "The above-median LaTeX renderer failed with exit code $LASTEXITCODE."
}

$pdf = Join-Path $report "output\main_v3_abovemedian.pdf"
if (-not (Test-Path -LiteralPath $pdf)) {
    throw "Expected report was not generated: $pdf"
}
Write-Host "Completed above-median replication outputs: $pdf"
