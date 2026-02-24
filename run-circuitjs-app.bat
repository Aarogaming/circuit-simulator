@echo off
setlocal

set "URL=https://www.falstad.com/circuit/circuitjs.html"
set "PF64=%ProgramFiles%"
set "PF86=%ProgramFiles(x86)%"
if not defined PF86 set "PF86=%PF64%"

set "CHROME=%PF64%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" if exist "%PF86%\Google\Chrome\Application\chrome.exe" set "CHROME=%PF86%\Google\Chrome\Application\chrome.exe"

if exist "%CHROME%" (
  start "" "%CHROME%" --app="%URL%"
  exit /b 0
)

set "EDGE=%PF86%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%PF64%\Microsoft\Edge\Application\msedge.exe"

if exist "%EDGE%" (
  start "" "%EDGE%" --app="%URL%"
  exit /b 0
)

start "" "%URL%"
