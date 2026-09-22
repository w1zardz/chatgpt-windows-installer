#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $root 'src\Installer.psm1'
$script:Passed = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Name)
    if ($Actual -cne $Expected) { throw "FAIL: $Name; expected <$Expected>, got <$Actual>" }
    $script:Passed++
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern, [string]$Name)
    $caught = $false
    try { & $Action | Out-Null } catch {
        $caught = $true
        if ($_.Exception.Message -notmatch $Pattern) { throw "FAIL: $Name; wrong error: $($_.Exception.Message)" }
    }
    if (-not $caught) { throw "FAIL: $Name; expected an error" }
    $script:Passed++
}

# Parse as the actual Windows PowerShell 5.1 engine in CI, not just PowerShell 7.
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object Extension -in @('.ps1', '.psm1')) {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal $parseErrors.Count 0 ('Syntax: ' + $file.Name)
}

$module = Import-Module $modulePath -Force -DisableNameChecking -PassThru
$feed = [pscustomobject]@{ schemaVersion = 1; buildVersion = '26.915.4065.0'; packageIdentity = 'OpenAI.Codex'; storeProductId = '9PLM9XGG6VKS' }
$release = ConvertTo-Release $feed 'x64'
Assert-Equal $release.Uri 'https://persistent.oaistatic.com/codex-app-prod/releases/26.915.4065.0/ChatGPT-x64.msix' 'Versioned official source'
Assert-Equal (ConvertTo-Release $feed 'arm64').Architecture 'arm64' 'ARM64 selection'
foreach ($invalid in @('../evil', '26.915.4065.0/evil', '26.915.4065.0;calc', '26.915.4065', '65536.1.1.1', '1.2.3.-1', '1.2.3.4`n')) {
    $copy = $feed | ConvertTo-Json | ConvertFrom-Json
    $copy.buildVersion = $invalid
    Assert-Throws { ConvertTo-Release $copy 'x64' } 'FEED_VERSION_INVALID' ('Reject version: ' + $invalid)
}
$copy = $feed | ConvertTo-Json | ConvertFrom-Json; $copy.packageIdentity = 'Other.App'
Assert-Throws { ConvertTo-Release $copy 'x64' } 'FEED_IDENTITY_MISMATCH' 'Reject changed identity'
$copy = $feed | ConvertTo-Json | ConvertFrom-Json; $copy.schemaVersion = 2
Assert-Throws { ConvertTo-Release $copy 'x64' } 'FEED_FORMAT_CHANGED' 'Reject new schema'
Assert-Throws { ConvertTo-Release ([pscustomobject]@{schemaVersion=1}) 'x64' } 'FEED_FORMAT_CHANGED' 'Missing feed properties'

Assert-OfficialUri $release.Uri
foreach ($url in @(
    'http://persistent.oaistatic.com/codex-app-prod/windows-store-update.json',
    'https://persistent.oaistatic.com.evil.example/codex-app-prod/windows-store-update.json',
    'https://persistent.oaistatic.com@evil.example/codex-app-prod/windows-store-update.json',
    'https://user:password@persistent.oaistatic.com/codex-app-prod/windows-store-update.json',
    'https://persistent.oaistatic.com:8443/codex-app-prod/windows-store-update.json',
    'https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json?url=evil',
    'https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json#fragment',
    'https://persistent.oaistatic.com/other/program.exe',
    'file:///C:/fake.msix'
)) { Assert-Throws { Assert-OfficialUri $url } 'UNTRUSTED_URL' ('Reject source: ' + $url) }

$installed = [pscustomobject]@{ Version = '26.903.8094.0'; Status = 'Ok' }
Assert-Equal (Get-UpdateDecision $null $release.Version) 'Install' 'Fresh install'
Assert-Equal (Get-UpdateDecision $installed $release.Version) 'Update' 'Older version'
$installed.Version = $release.Version
Assert-Equal (Get-UpdateDecision $installed $release.Version) 'Current' 'Idempotence'
$installed.Version = '99.0.0.0'
Assert-Equal (Get-UpdateDecision $installed $release.Version) 'NewerInstalled' 'No downgrade'
$installed.Status = 'Modified'
Assert-Equal (Get-UpdateDecision $installed $release.Version) 'NeedsRepair' 'Unhealthy package is not current'
Assert-Equal (Get-InstallOutcome $null $release.Version) 'PendingRegistration' 'No registration is not success'
$installed.Status = 'Ok'; $installed.Version = '26.903.8094.0'
Assert-Equal (Get-InstallOutcome $installed $release.Version) 'PendingRegistration' 'Old registration is pending'
$installed.Version = $release.Version
Assert-Equal (Get-InstallOutcome $installed $release.Version) 'Installed' 'Verify registered version'

$metadata = [pscustomobject]@{ Name = 'OpenAI.Codex'; Publisher = 'CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B'; Version = $release.Version; Architecture = 'x64'; MinWindowsVersion = '10.0.19041.0'; Dependencies = @() }
Assert-PackageMetadata $metadata $release '10.0.26100.0'
foreach ($change in @(@('Name','Malicious.App','PACKAGE_IDENTITY_MISMATCH'), @('Publisher','CN=Other','PACKAGE_IDENTITY_MISMATCH'), @('Architecture','arm64','0x80073D10'), @('Version','1.0.0.0','PACKAGE_VERSION_MISMATCH'), @('MinWindowsVersion','10.0.99999.0','0x80073CFD'))) {
    $copy = $metadata | ConvertTo-Json | ConvertFrom-Json; $copy.($change[0]) = $change[1]
    Assert-Throws { Assert-PackageMetadata $copy $release '10.0.26100.0' } $change[2] ('Reject package ' + $change[0])
}

Assert-Equal ((Get-ErrorCodes 'Wrapper 0x80073cf6, cause 0x80073d28 and duplicate 0X80073D28') -join ',') '0x80073CF6,0x80073D28' 'Extract and normalize error codes'
try { throw 'Wrapper 0x80073CF6 caused by 0x80073D28' } catch { Assert-Equal (Get-ExceptionCode $_) '0x80073D28' 'Prefer actionable nested error' }
try { throw (New-Object ComponentModel.Win32Exception(1223)) } catch { Assert-Equal (Get-ExceptionCode $_) '0x800704C7' 'Recognize cancelled UAC prompt' }
$catalog = Get-Content -LiteralPath (Join-Path $root 'src\errors.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Equal @($catalog.code | Select-Object -Unique).Count $catalog.Count 'Unique error mappings'
foreach ($entry in $catalog) {
    $advice = Get-ErrorAdvice $entry.code
    Assert-Equal $advice.code $entry.code ('Mapping ' + $entry.code)
    if (-not $advice.action -or $advice.summary -match 'not in this version') { throw ('Missing advice for ' + $entry.code) }
}
Assert-Equal (Get-ErrorAdvice '0xDEADBEEF').code '0xDEADBEEF' 'Unknown code preserved'

$snapshot = [pscustomobject]@{
    windowsVersion='10.0.26100.0'; architecture='x64'; availableDiskBytes=@(10GB)
    pendingReboot=$false; services=@(); configuredPolicies=@(); legacyAppDetected=$false
}
Assert-Equal @(Get-PreflightFindings $snapshot | Where-Object severity -eq 'blocker').Count 0 'Normal preflight'
$snapshot.architecture='unsupported'
Assert-Equal @(Get-PreflightFindings $snapshot | Where-Object code -eq 'UNSUPPORTED_ARCHITECTURE').Count 1 'Reject 32-bit Windows'
$snapshot.architecture='arm64'; $snapshot.windowsVersion='10.0.17763.0'
Assert-Equal @(Get-PreflightFindings $snapshot | Where-Object code -eq 'WINDOWS_TOO_OLD').Count 1 'Old Windows'
$snapshot.windowsVersion='10.0.26100.0'; $snapshot.availableDiskBytes=@(1GB)
Assert-Equal @(Get-PreflightFindings $snapshot | Where-Object code -eq 'LOW_DISK_SPACE').Count 1 'Low disk space'
$snapshot.availableDiskBytes=@(10GB); $snapshot.services=@([pscustomobject]@{name='AppXSvc';status='Stopped';startType='Manual'})
Assert-Equal @(Get-PreflightFindings $snapshot | Where-Object severity -eq 'blocker').Count 0 'Stopped trigger-start service is normal'

# Exercise the real manifest reader with a small generated package (no executables).
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('chatgpt-installer-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempRoot
$oldLocal = $env:LOCALAPPDATA
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath = Join-Path $tempRoot 'test.msix'
    $archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    $entry = $archive.CreateEntry('AppxManifest.xml')
    $writer = New-Object IO.StreamWriter($entry.Open())
    $writer.Write('<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"><Identity Name="OpenAI.Codex" Publisher="CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B" Version="26.915.4065.0" ProcessorArchitecture="x64"/><Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0"/></Dependencies></Package>')
    $writer.Dispose(); $archive.Dispose()
    Assert-Equal (Get-MsixMetadata $zipPath).Name 'OpenAI.Codex' 'Read manifest without extracting executable files'
    Assert-Throws { Confirm-OfficialPackage $zipPath $release '10.0.26100.0' } 'PACKAGE_SIGNATURE_INVALID' 'Reject unsigned package before install'

    # Full workflow simulations. All package mutations and elevation are mocked.
    $env:LOCALAPPDATA = $tempRoot
    foreach ($scenario in @('Current','Update','Pending','SignatureFailure','DownloadFailure','ChangedAccount','Offline','MissingDependency','Elevation','PolicyFailure','UnknownFailure')) {
        Remove-Module Installer -Force
        $module = Import-Module $modulePath -Force -DisableNameChecking -PassThru
        & $module {
            param($Scenario)
            $script:Scenario = $Scenario
            $script:MutexName = 'Local\ChatGPTWindowsInstaller.Tests.' + $PID
            $script:InstallCalls = 0; $script:DownloadCalls = 0; $script:FeedCalls = 0; $script:ElevationCalls = 0
            function script:Get-CurrentUserSid { 'S-1-5-21-1-1001' }
            function script:Test-IsAdministrator { $script:Scenario -ne 'Elevation' }
            function script:Get-SystemSnapshot {
                [pscustomobject]@{windowsVersion='10.0.26100.0';architecture='x64';availableDiskBytes=@(10GB);pendingReboot=$false;services=@();configuredPolicies=@();legacyAppDetected=$false}
            }
            function script:Get-RecentDeploymentErrors { @() }
            function script:Get-LatestRelease {
                param($Architecture)
                $script:FeedCalls++
                [pscustomobject]@{Version='26.915.4065.0';Architecture='x64';Uri='https://persistent.oaistatic.com/codex-app-prod/releases/26.915.4065.0/ChatGPT-x64.msix'}
            }
            function script:Get-InstalledPackage {
                $version = if ($script:Scenario -eq 'Current' -or ($script:InstallCalls -gt 0 -and $script:Scenario -ne 'Pending')) { '26.915.4065.0' } else { '26.903.8094.0' }
                [pscustomobject]@{Version=$version;Status='Ok'}
            }
            function script:Save-OfficialPackage {
                param($Release,$Destination)
                $script:DownloadCalls++
                if ($script:Scenario -eq 'DownloadFailure') { throw 'DOWNLOAD_INCOMPLETE' }
                [IO.File]::WriteAllText($Destination,'mock-package')
            }
            function script:Confirm-OfficialPackage {
                param($Path,$Release,$WindowsVersion)
                if ($script:Scenario -eq 'SignatureFailure') { throw 'PACKAGE_SIGNATURE_INVALID' }
                [pscustomobject]@{Metadata=[pscustomobject]@{Dependencies=@()};Sha256=('A'*64);SignatureStatus='Valid'}
            }
            function script:Get-DependencyFindings {
                param($Metadata)
                if ($script:Scenario -eq 'MissingDependency') { New-Finding 'DEPENDENCY_MISSING' 'blocker' 'Missing' 'Use official installer.' }
            }
            function script:Add-AppxPackage {
                [CmdletBinding()]param($Path,[switch]$DeferRegistrationWhenPackagesAreInUse)
                $script:InstallCalls++
                if (-not $DeferRegistrationWhenPackagesAreInUse) { throw 'Test requires deferred registration' }
                if ($script:Scenario -eq 'PolicyFailure') { throw '0x80073D01' }
                if ($script:Scenario -eq 'UnknownFailure') { throw 'Private C:\Users\SecretName\data token=private 0xDEADBEEF' }
            }
            function script:Start-ElevatedInstaller {
                param($EntryPath,$Language,$CallerSid,[switch]$NoPause)
                $script:ElevationCalls++
                return 10
            }
        } $scenario
        $params = @{ Mode='Auto'; Language='en'; NoPause=$true; EntryPath=(Join-Path $root 'Install-ChatGPT.ps1') }
        if ($scenario -eq 'ChangedAccount') { $params.CallerSid='S-1-5-21-2-1002' }
        if ($scenario -eq 'Offline') { $params.Mode='Diagnose'; $params.Offline=$true }
        $result = Invoke-ChatGPTInstaller @params 6>$null
        $counts = & $module { @($script:InstallCalls, $script:DownloadCalls, $script:FeedCalls, $script:ElevationCalls) }
        $expected = switch ($scenario) {
            'Current' { @(0,0,0,1,0) }
            'Update' { @(0,1,1,1,0) }
            'Pending' { @(10,1,1,1,0) }
            'SignatureFailure' { @(1,0,1,1,0) }
            'DownloadFailure' { @(1,0,1,1,0) }
            'ChangedAccount' { @(2,0,0,0,0) }
            'Offline' { @(0,0,0,0,0) }
            'MissingDependency' { @(2,0,1,1,0) }
            'Elevation' { @(10,0,0,1,1) }
            'PolicyFailure' { @(1,1,1,1,0) }
            'UnknownFailure' { @(1,1,1,1,0) }
        }
        Assert-Equal $result $expected[0] ($scenario + ' exit status')
        for ($i=0; $i -lt 4; $i++) { Assert-Equal $counts[$i] $expected[$i+1] ($scenario + ' side effects ' + $i) }
    }
    foreach ($reportFile in Get-ChildItem -LiteralPath (Join-Path $tempRoot 'ChatGPTWindowsInstaller\reports') -Filter '*.json') {
        $contents = Get-Content -LiteralPath $reportFile.FullName -Raw -Encoding UTF8
        Assert-Equal ($contents -match 'SecretName|token=private|S-1-5-21-|C:\\\\Users\\\\') $false 'No raw exception, username, SID, or user path in report'
        $null = $contents | ConvertFrom-Json -ErrorAction Stop
    }
}
finally {
    $env:LOCALAPPDATA = $oldLocal
    Remove-Module Installer -Force -ErrorAction SilentlyContinue
    # Delete only the test-owned, resolved temporary folder.
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'chatgpt-installer-tests-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host ("PASS: {0} assertions. No real applications installed, removed, or updated." -f $script:Passed) -ForegroundColor Green
