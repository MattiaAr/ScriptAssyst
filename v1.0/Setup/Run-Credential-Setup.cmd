@echo off
setlocal
set "SCRIPT=%~dp0Credential-Setup.ps1"
if not exist "%SCRIPT%" (
  echo Errore: Credential-Setup.ps1 non trovato nella cartella Setup.
  pause
  exit /b 2
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo Errore: Windows PowerShell 5.1 non e disponibile.
  pause
  exit /b 3
)
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo Setup non completato. Codice di uscita: %RESULT%
  pause
)
exit /b %RESULT%
