@echo off
setlocal

set "ROOT=%~dp0"
set "JAR=%ROOT%src\circuit.jar"
set "PACKAGE_NAME=circuit-simulator-offline"
set "DIST_DIR=%ROOT%dist"
set "STAGE_DIR=%DIST_DIR%\%PACKAGE_NAME%-stage"

if not exist "%JAR%" (
  echo Missing %JAR%
  echo Build the jar first in the src folder:
  echo   cd src
  echo   javac *.java
  echo   jar cfm circuit.jar Manifest.txt *.class *.txt circuits\
  echo.
  echo Or run 'make' then 'make jar'.
  exit /b 1
)

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%"
mkdir "%STAGE_DIR%"
if not exist "%STAGE_DIR%" exit /b 1

mkdir "%STAGE_DIR%\src"
copy /y "%ROOT%run-circuitjs-offline.bat" "%STAGE_DIR%\run-circuitjs-offline.bat" >nul
copy /y "%ROOT%offline-package-readme.txt" "%STAGE_DIR%\README.txt" >nul
copy /y "%JAR%" "%STAGE_DIR%\src\circuit.jar" >nul

for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%T"
set "STAMP=%STAMP::=-%"
set "OUT=%DIST_DIR%\%PACKAGE_NAME%-%STAMP%.zip"

powershell -NoProfile -Command "Compress-Archive -Path '%STAGE_DIR%\*' -DestinationPath '%OUT%' -Force"

rmdir /s /q "%STAGE_DIR%"

if exist "%OUT%" (
  echo.
  echo Package created: %OUT%
  exit /b 0
) else (
  echo Failed to create zip package.
  exit /b 1
)
