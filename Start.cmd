@echo off
setlocal DisableDelayedExpansion
title ChatGPT Windows Installer
if not exist "%~dp0Install-ChatGPT.ps1" goto missing
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ChatGPT.ps1" %*
set "RESULT=%ERRORLEVEL%"
exit /b %RESULT%

:missing
rem Started from inside the ZIP or from a partial copy: keep the window open so the message is visible.
echo Install-ChatGPT.ps1 was not found next to Start.cmd.
echo Extract the entire ZIP to a folder first, then run Start.cmd from that folder.
pause
exit /b 1
