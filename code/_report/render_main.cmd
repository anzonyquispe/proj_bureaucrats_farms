@echo off
setlocal

set "REPORT_DIR=%~dp0"
set "OUTPUT_DIR=%REPORT_DIR%output"

where pdflatex >nul 2>&1
if errorlevel 1 (
    echo ERROR: pdflatex was not found on PATH. Install MiKTeX and reopen the terminal.
    exit /b 1
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

pushd "%REPORT_DIR%"
echo [1/3] Updating references (draft pass)...
pdflatex -interaction=nonstopmode -halt-on-error -file-line-error -draftmode -output-directory=output main.tex > "%OUTPUT_DIR%\main_pass_1.log" 2>&1
if errorlevel 1 goto :build_failed

echo [2/3] Stabilizing references (draft pass)...
pdflatex -interaction=nonstopmode -halt-on-error -file-line-error -draftmode -output-directory=output main.tex > "%OUTPUT_DIR%\main_pass_2.log" 2>&1
if errorlevel 1 goto :build_failed

echo [3/3] Writing final PDF...
pdflatex -interaction=nonstopmode -halt-on-error -file-line-error -output-directory=output main.tex > "%OUTPUT_DIR%\main_pass_3.log" 2>&1
if errorlevel 1 goto :build_failed
popd

echo.
echo Rendered: %OUTPUT_DIR%\main.pdf
exit /b 0

:build_failed
popd
echo.
echo ERROR: LaTeX build failed. See %OUTPUT_DIR%\main.log
exit /b 1
