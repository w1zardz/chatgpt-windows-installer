#Requires -Version 5.1
<#
.SYNOPSIS
Diagnose, install, or update the official ChatGPT desktop app for Windows.
.DESCRIPTION
Double-click Start.cmd for automatic mode. Diagnose.cmd never installs an app.
The installer asks Windows for administrator consent when an update is needed.
If ChatGPT is open, the administrator window waits until it is closed, then installs.
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Diagnose', 'Download')][string]$Mode = 'Auto',
    [ValidateSet('Auto', 'en', 'ru')][string]$Language = 'Auto',
    [switch]$Offline,
    # Non-interactive: no final pause and no waiting for ChatGPT to close.
    [switch]$NoPause,
    # Internal UAC handoff: never install into a different administrator account.
    [string]$CallerSid
)

$ErrorActionPreference = 'Stop'
$exitCode = 1
$handoff = [ref]$false
try {
    Import-Module (Join-Path $PSScriptRoot 'src\Installer.psm1') -Force -ErrorAction Stop
    $exitCode = Invoke-ChatGPTInstaller -Mode $Mode -Language $Language -Offline:$Offline -CallerSid $CallerSid -NoPause:$NoPause -EntryPath $PSCommandPath -Handoff $handoff
}
catch {
    # Never print unfiltered exceptions: network errors may contain proxy credentials.
    Write-Host 'The installer could not start. Use Windows PowerShell 5.1 and extract the entire ZIP first.' -ForegroundColor Red
    Write-Host 'Не удалось запустить скрипт. Распакуйте весь ZIP и запустите Start.cmd через Windows PowerShell 5.1.' -ForegroundColor Red
}
finally {
    if (-not $NoPause -and -not $handoff.Value) { [void](Read-Host 'Press Enter to close / Нажмите Enter для выхода') }
}
exit $exitCode
