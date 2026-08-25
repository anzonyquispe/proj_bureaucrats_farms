@echo off
setlocal

set "REPORT_DIR=%~dp0"
set "REPO_DIR=%REPORT_DIR%..\.."
set "OUTPUT_DIR=%REPORT_DIR%output"
set "TEX_FILE=main_v3_abovemedian.tex"
set "JOB_NAME=main_v3_abovemedian"

where pdflatex >nul 2>&1
if errorlevel 1 (
    echo ERROR: pdflatex was not found on PATH. Install MiKTeX and reopen the terminal.
    exit /b 1
)

rem Do not let LaTeX's fallback file lookup silently mix unrestricted results
rem into the above-median report when post-processing is incomplete.
for %%F in (
    "figures\stacked_event_study_5pre_rural_1_ori_rice_high.png"
    "figures\stacked_event_study_pop_5pre_rural_1_ori_rice_high.png"
    "figures\_app_16_polischar_fe03_evst_main_rural_acpop_1_ori_rice_high.png"
    "figures\_app_17_5km_fe12_evst_all_rural_fe03_1_ori_rice_high.png"
    "tables\main_did_downup_ac_rural_acpop_rice_high.tex"
    "tables\_main_4_protest_5km_fe12_did_downup_rural_acpop_new_rice_high.tex"
    "tables\_main_5_polischar_fe12_did_downup_inter_rural_acpop_rice_high.tex"
) do (
    if not exist "%REPO_DIR%\%%~F" (
        echo ERROR: Missing above-median output: %REPO_DIR%\%%~F
        echo Run code\_stacked_downup_replication\run_abovemedian_postprocessing.ps1 first.
        exit /b 1
    )
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

pushd "%REPORT_DIR%"
echo [1/3] Updating above-median references (draft pass)...
pdflatex -interaction=nonstopmode -halt-on-error -file-line-error -draftmode -jobname=%JOB_NAME% -output-directory=output %TEX_FILE% > "%OUTPUT_DIR%\%JOB_NAME%_pass_1.log" 2>&1
if errorlevel 1 goto :build_failed

echo [2/3] Stabilizing above-median references (draft pass)...
pdflatex -interaction=nonstopmode -halt-on-error -file-line-error -draftmode -jobname=%JOB_NAME% -output-directory=output %TEX_FILE% > "%OUTPUT_DIR%\%JOB_NAME%_pass_2.log" 2>&1
if errorlevel 1 goto :build_failed

echo [3/3] Writing final above-median PDF...
pdflatex -interaction=nonstopmode -halt-on-error -file-line-error -jobname=%JOB_NAME% -output-directory=output %TEX_FILE% > "%OUTPUT_DIR%\%JOB_NAME%_pass_3.log" 2>&1
if errorlevel 1 goto :build_failed
popd

echo.
echo Rendered: %OUTPUT_DIR%\%JOB_NAME%.pdf
exit /b 0

:build_failed
popd
echo.
echo ERROR: LaTeX build failed. See %OUTPUT_DIR%\%JOB_NAME%.log
exit /b 1
