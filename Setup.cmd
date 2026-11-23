@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0setup.ps1" %*
if errorlevel 1 (
  echo.
  pause
  exit /b 1
)
