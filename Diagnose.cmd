@echo off
setlocal DisableDelayedExpansion
call "%~dp0Start.cmd" -Mode Diagnose %*
exit /b %ERRORLEVEL%
