@echo off
setlocal

set "ROOT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "LAUNCHER=%ROOT%run-circuit-simulator.ps1"
set "NATIVE_EXE=%ROOT%Circuit Simulator\Circuit Simulator.exe"
set "WEB_ZIP=%ROOT%circuitjs-offline-web-release.zip"
set "CFG_DIR=%ROOT%.circuit-simulator\config"

set "HAS_PS=0"
if exist "%PS%" if exist "%LAUNCHER%" (
  "%PS%" -NoProfile -Command "exit 0" >nul 2>nul
  if not errorlevel 1 set "HAS_PS=1"
)

if not exist "%NATIVE_EXE%" goto :missing_native

if not exist "%CFG_DIR%" mkdir "%CFG_DIR%" >nul 2>nul

:preflight
cls
echo ===============================================
echo        Circuit Simulator Preflight Check
echo ===============================================
echo.
if exist "%NATIVE_EXE%" (
  echo [OK] Native executable found
) else (
  echo [FAIL] Native executable missing
)

if "%HAS_PS%"=="1" (
  echo [OK] PowerShell engine available
) else (
  echo [WARN] PowerShell unavailable or broken
)

if exist "%WEB_ZIP%" (
  echo [OK] Web offline package found
) else (
  echo [WARN] Web offline package missing
)

if exist "%CFG_DIR%" (
  echo [OK] Config directory available: %CFG_DIR%
) else (
  echo [WARN] Config directory unavailable
)

echo.
echo Press any key to continue...
pause >nul

:menu
cls
echo ===============================================
echo           Circuit Simulator Launcher
echo ===============================================
echo.
echo 1^) Launch configured mode
echo 2^) Launch Native now
echo 3^) Launch Web now
echo 4^) Configure startup options
echo 5^) Repair .ps1 file association
echo 6^) Exit
echo.
set /p CHOICE=Select option [1-6]: 

if "%CHOICE%"=="1" goto :launch_default
if "%CHOICE%"=="2" goto :launch_native
if "%CHOICE%"=="3" goto :launch_web
if "%CHOICE%"=="4" goto :configure
if "%CHOICE%"=="5" goto :repair_ps1
if "%CHOICE%"=="6" exit /b 0
goto :menu

:launch_default
if "%HAS_PS%"=="1" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%"
) else (
  start "Circuit Simulator" "%NATIVE_EXE%"
)
goto :done

:launch_native
if "%HAS_PS%"=="1" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" -Mode native
) else (
  start "Circuit Simulator" "%NATIVE_EXE%"
)
goto :done

:launch_web
if not "%HAS_PS%"=="1" (
  echo.
  echo Web mode requires working PowerShell on this PC.
  echo Launching native mode instead.
  start "Circuit Simulator" "%NATIVE_EXE%"
  pause
  goto :menu
)
if not exist "%WEB_ZIP%" (
  echo.
  echo Web package not found: %WEB_ZIP%
  echo Launching native mode instead.
  start "Circuit Simulator" "%NATIVE_EXE%"
  pause
  goto :menu
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" -Mode web
goto :done

:configure
if not "%HAS_PS%"=="1" (
  echo.
  echo Configure mode requires working PowerShell on this PC.
  pause
  goto :menu
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" -Configure
goto :done

:repair_ps1
echo.
echo Repairing .ps1 association...
assoc .ps1=Microsoft.PowerShellScript.1
ftype Microsoft.PowerShellScript.1="%PS%" "%%1" %%*
echo.
echo Done. If access was denied, rerun this launcher as Administrator.
pause
goto :menu

:missing_native
echo Missing native executable:
echo %NATIVE_EXE%
pause
exit /b 1

:done
exit /b 0
