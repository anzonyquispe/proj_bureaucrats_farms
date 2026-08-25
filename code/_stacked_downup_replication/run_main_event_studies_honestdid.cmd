@echo off
setlocal EnableExtensions

rem Generate the production event-study and HonestDiD figures for:
rem   1. main downup_ac_pop analysis;
rem   2. politician analysis using selected FE03;
rem   3. protest analysis (baseline and high-rice-production moderator).
rem This launcher only post-processes existing CSV estimates. It does not run
rem Stata regressions.

for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
set "TABLE_DIR=%REPO%\tables"
set "SOURCE_DIR=%TABLE_DIR%\exploratory_analysis\cohort_eventtime_fe_sweep"
set "SOURCE_STEM=politician_byprov_cohorttime_fe03_event_rural_acpop_all"
set "TARGET_STEM=_app_16_polischar_fe03_evst_main_acpop_rural"
set "PLOT_SCRIPT=%REPO%\code\_stacked_downup_replication\plotting_event_studies.R"

rem Promote the selected politician FE03 estimates to the production filename.
if not exist "%SOURCE_DIR%\%SOURCE_STEM%.csv" (
    echo ERROR: Missing politician FE03 CSV: "%SOURCE_DIR%\%SOURCE_STEM%.csv"
    exit /b 66
)
copy /Y "%SOURCE_DIR%\%SOURCE_STEM%.csv" "%TABLE_DIR%\%TARGET_STEM%.csv" >nul || exit /b 1
if exist "%SOURCE_DIR%\%SOURCE_STEM%.ster" (
    copy /Y "%SOURCE_DIR%\%SOURCE_STEM%.ster" "%TABLE_DIR%\%TARGET_STEM%.ster" >nul || exit /b 1
)
if exist "%SOURCE_DIR%\%SOURCE_STEM%_scalars.csv" (
    copy /Y "%SOURCE_DIR%\%SOURCE_STEM%_scalars.csv" "%TABLE_DIR%\%TARGET_STEM%_scalars.csv" >nul || exit /b 1
)

if not exist "%TABLE_DIR%\stacked_event_study_pop_5pre_rural.csv" (
    echo ERROR: Missing main population event-study CSV.
    exit /b 66
)
if not exist "%TABLE_DIR%\_app_17_5km_fe12_evst_all_rural.csv" (
    echo ERROR: Missing protest event-study CSV.
    exit /b 66
)

set "RSCRIPT=C:\Program Files\R\R-4.5.0\bin\Rscript.exe"
if not exist "%RSCRIPT%" set "RSCRIPT=Rscript"

"%RSCRIPT%" "%PLOT_SCRIPT%" ^
    --root "%REPO%" ^
    --output-root "%REPO%" ^
    --families main,protest ^
    --cases final_stacked_population_baseline,final_politician_fe03_baseline ^
    --honest ^
    --honest-cores 5
if errorlevel 1 exit /b %errorlevel%

echo Completed main population, politician FE03, and protest event-study/HonestDiD figures.
endlocal
