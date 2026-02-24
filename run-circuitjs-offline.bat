@echo off
setlocal

set "ROOT=%~dp0"
set "JAR=%ROOT%src\circuit.jar"

if not exist "%JAR%" (
  echo Missing %JAR%
  echo Build the jar first from the src folder:
  echo   cd src
  echo   javac *.java
  echo   jar cfm circuit.jar Manifest.txt *.class *.txt circuits\
  echo.
  echo Or run 'make' then 'make jar'.
  exit /b 1
)

set "JAVA="

if defined JAVA_HOME if exist "%JAVA_HOME%\bin\javaw.exe" set "JAVA=%JAVA_HOME%\bin\javaw.exe"
if not defined JAVA if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA=%JAVA_HOME%\bin\java.exe"

if not defined JAVA where javaw >nul 2>nul && set "JAVA=javaw.exe"
if not defined JAVA where java >nul 2>nul && set "JAVA=java.exe"

if not defined JAVA (
  echo Java runtime not found.
  echo Install Java 8+ or set JAVA_HOME.
  exit /b 1
)

start "Circuit Simulator" "%JAVA%" -jar "%JAR%"
exit /b 0
