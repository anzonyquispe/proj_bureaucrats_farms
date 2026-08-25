@echo off
setlocal EnableExtensions

rem Generate the politician FE03 original, rotated, and HonestDiD figures from
rem the production event-study result. No Stata regression is rerun.

for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
set "TABLE_DIR=%REPO%\tables"
set "PLOT_SCRIPT=%REPO%\code\_stacked_downup_replication\plotting_event_studies.R"

if not exist "%TABLE_DIR%\_app_16_polischar_fe12_evst_all_rural_acpop_controls_both.csv" (
    echo ERROR: Missing production politician FE03 CSV.
    exit /b 66
)

set "RSCRIPT=C:\Program Files\R\R-4.5.0\bin\Rscript.exe"
if not exist "%RSCRIPT%" set "RSCRIPT=Rscript"

"%RSCRIPT%" "%PLOT_SCRIPT%" ^
    --root "%REPO%" ^
    --output-root "%REPO%" ^
    --families main ^
    --cases final_politician_fe03_baseline ^
    --honest ^
    --honest-cores 5
if errorlevel 1 exit /b %errorlevel%

for %%F in (
    "%REPO%\figures\_app_16_polischar_fe03_evst_main_rural_acpop_1_ori.png"
    "%REPO%\figures\_app_16_polischar_fe03_evst_main_rural_acpop_1_rotated.png"
    "%REPO%\figures\_app_16_polischar_fe03_evst_main_rural_acpop_1_honest2.png"
    "%REPO%\figures\_app_16_polischar_fe03_evst_main_rural_acpop_1_rot_honest2.png"
) do (
    if not exist "%%~F" (
        echo ERROR: Missing expected output: %%~F
        exit /b 1
    )
)

echo Completed selected politician FE03 event-study and HonestDiD figures.
endlocal
