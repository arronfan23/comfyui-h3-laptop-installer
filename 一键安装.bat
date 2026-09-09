@echo off
rem SanMaoCloud - ComfyUI H3 one-click installer (Laptop edition)
cd /d %~dp0
title SanMaoCloud ComfyUI H3 Installer
if not exist "%~dp0installer\install.ps1" (
  echo [ERROR] installer\install.ps1 not found!
  echo.
  echo Please extract the whole ZIP first:
  echo right-click the downloaded ZIP, choose "Extract All...",
  echo then open the extracted folder and double-click this file again.
  echo.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\install.ps1" %*
echo.
echo Installer finished. If anything failed, send a screenshot of this
echo window and the file installer\install.log back for help.
pause
