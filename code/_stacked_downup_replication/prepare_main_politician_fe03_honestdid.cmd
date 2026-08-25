@echo off
setlocal EnableExtensions

rem Promote the current exploratory FE03 politician event-study result to the
rem main-results naming convention, then generate original, rotated, and both
rem HonestDiD sensitivity plots. No Stata regression is rerun.

for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
set "SOURCE_DIR=%REPO%\tables\exploratory_analysis\cohort_eventtime_fe_sweep"
set "TABLE_DIR=%REPO%\tables"
set "SOURCE_STEM=politician_byprov_cohorttime_fe03_event_rural_acpop_all"
set "TARGET_STEM=_app_16_polischar_fe03_evst_main_acpop_rural"
set "PLOT_SCRIPT=%REPO%\code\_stacked_downup_replication\plotting_event_studies.R"

if not exist "%SOURCE_DIR%\%SOURCE_STEM%.csv" (
    echo ERROR: Missing FE03 CSV: "%SOURCE_DIR%\%SOURCE_STEM%.csv"
    exit /b 66
)
if not exist "%SOURCE_DIR%\%SOURCE_STEM%.ster" (
    echo ERROR: Missing FE03 STER: "%SOURCE_DIR%\%SOURCE_STEM%.ster"
    exit /b 66
)

copy /Y "%SOURCE_DIR%\%SOURCE_STEM%.csv" "%TABLE_DIR%\%TARGET_STEM%.csv" >nul || exit /b 1
copy /Y "%SOURCE_DIR%\%SOURCE_STEM%.ster" "%TABLE_DIR%\%TARGET_STEM%.ster" >nul || exit /b 1
if exist "%SOURCE_DIR%\%SOURCE_STEM%_scalars.csv" (
    copy /Y "%SOURCE_DIR%\%SOURCE_STEM%_scalars.csv" "%TABLE_DIR%\%TARGET_STEM%_scalars.csv" >nul || exit /b 1
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
