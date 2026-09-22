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
Assert-OfficialUri 'https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix'
Assert-OfficialUri 'https://persistent.oaistatic.com/codex-app-prod/ChatGPT-arm64.msix'
foreach ($url in @(
    'http://persistent.oaistatic.com/codex-app-prod/windows-store-update.json',
    'https://persistent.oaistatic.com.evil.example/codex-app-prod/windows-store-update.json',
    'https://persistent.oaistatic.com@evil.example/codex-app-prod/windows-store-update.json',
    'https://user:password@persistent.oaistatic.com/codex-app-prod/windows-store-update.json',
    'https://persistent.oaistatic.com:8443/codex-app-prod/windows-store-update.json',
    'https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json?url=evil',
    'https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json#fragment',
    'https://persistent.oaistatic.com/other/program.exe',
    'https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x86.msix',
    'https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix?redirect=evil',
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
$olderMetadata = $metadata | ConvertTo-Json | ConvertFrom-Json
$olderMetadata.Version = '26.910.1.0'
Assert-PackageMetadata $olderMetadata $release '10.0.26100.0' -AllowVersionDifference
Assert-Throws { Assert-PackageMetadata $olderMetadata $release '10.0.26100.0' } 'PACKAGE_VERSION_MISMATCH' 'Versioned download remains strictly pinned'
$olderMetadata.Publisher = 'CN=Other'
Assert-Throws { Assert-PackageMetadata $olderMetadata $release '10.0.26100.0' -AllowVersionDifference } 'PACKAGE_IDENTITY_MISMATCH' 'Fallback never relaxes publisher validation'
foreach ($change in @(@('Name','Malicious.App','PACKAGE_IDENTITY_MISMATCH'), @('Publisher','CN=Other','PACKAGE_IDENTITY_MISMATCH'), @('Architecture','arm64','0x80073D10'), @('Version','1.0.0.0','PACKAGE_VERSION_MISMATCH'), @('MinWindowsVersion','10.0.99999.0','0x80073CFD'))) {
    $copy = $metadata | ConvertTo-Json | ConvertFrom-Json; $copy.($change[0]) = $change[1]
    Assert-Throws { Assert-PackageMetadata $copy $release '10.0.26100.0' } $change[2] ('Reject package ' + $change[0])
}

Assert-Equal ((Get-ErrorCodes 'Wrapper 0x80073cf6, cause 0x80073d28 and duplicate 0X80073D28') -join ',') '0x80073CF6,0x80073D28' 'Extract and normalize error codes'
try { throw 'Wrapper 0x80073CF6 caused by 0x80073D28' } catch { Assert-Equal (Get-ExceptionCode $_) '0x80073D28' 'Prefer actionable nested error' }
try { throw (New-Object ComponentModel.Win32Exception(1223)) } catch { Assert-Equal (Get-ExceptionCode $_) '0x800704C7' 'Recognize cancelled UAC prompt' }
# Reproduce .NET's wrapped WebException without network requests.
Add-Type -TypeDefinition @'
using System;
using System.Net;
public sealed class InstallerTestResponse : WebResponse {
    public HttpStatusCode StatusCode { get; private set; }
    public InstallerTestResponse(int status) { StatusCode = (HttpStatusCode)status; }
}
public static class InstallerTestNetwork {
    public static void Fail(int status) {
        throw new WebException("Private https://user:secret@proxy.invalid/", null,
            WebExceptionStatus.ProtocolError, new InstallerTestResponse(status));
    }
    public static void Timeout() {
        throw new WebException("Private proxy secret", WebExceptionStatus.Timeout);
    }
}
// Serves bytes from an offset and can drop the connection like a real response stream.
public sealed class InstallerTestStream : System.IO.Stream {
    private readonly byte[] data;
    private long position;
    private readonly long failAt;
    public InstallerTestStream(byte[] data, long start, long failAt) { this.data = data; this.position = start; this.failAt = failAt; }
    public override int Read(byte[] buffer, int offset, int count) {
        if (failAt >= 0 && position >= failAt) {
            throw new System.IO.IOException("Unable to read data from the transport connection.", new System.Net.Sockets.SocketException(10054));
        }
        long limit = failAt >= 0 ? Math.Min(data.Length, failAt) : data.Length;
        int length = (int)Math.Min(count, limit - position);
        if (length <= 0) { return 0; }
        Buffer.BlockCopy(data, (int)position, buffer, offset, length);
        position += length;
        return length;
    }
    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { throw new NotSupportedException(); } }
    public override long Position { get { return position; } set { throw new NotSupportedException(); } }
    public override void Flush() { }
    public override long Seek(long offset, System.IO.SeekOrigin origin) { throw new NotSupportedException(); }
    public override void SetLength(long value) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
}
'@
try { [InstallerTestNetwork]::Fail(404) } catch {
    $network = & $module { param($Record) Get-NetworkException $Record } $_
    Assert-Equal ([int]$network.Response.StatusCode) 404 'Find HTTP 404 inside method invocation wrapper'
}
foreach ($case in @(
    @({ throw (New-Object IO.IOException('Unable to read data from the transport connection.', (New-Object Net.Sockets.SocketException(10054)))) }, $true, 'Dropped connection is transient'),
    @({ throw (New-Object IO.IOException('There is not enough space on the disk.', -2147024784)) }, $false, 'Full disk is not transient'),
    @({ [InstallerTestNetwork]::Timeout() }, $true, 'Wrapped timeout is transient'),
    @({ [InstallerTestNetwork]::Fail(403) }, $false, 'HTTP 403 is not transient')
)) {
    $caught = $false
    try { & $case[0] } catch { $caught = $true; Assert-Equal (& $module { param($Record) Test-TransientNetworkFailure $Record } $_) $case[1] $case[2] }
    Assert-Equal $caught $true ($case[2] + ' fixture threw')
}
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
$oldProgramData = $env:ProgramData
try {
    # Execute the real encoded handoff command in a child Windows PowerShell,
    # replacing only the UAC launch and the fixture's installation work.
    # U+2019 is also a PowerShell quote character, like the ASCII apostrophe.
    $handoffFixture = Join-Path $tempRoot ("handoff user's O" + [char]0x2019 + "Brien fixture.ps1")
    & $module {
        function script:Start-Process {
            param($FilePath,$Verb,$WindowStyle,[switch]$Wait,[switch]$PassThru,$ArgumentList)
            if ($Verb -ne 'RunAs') { throw 'Handoff must request UAC in production' }
            Microsoft.PowerShell.Management\Start-Process -FilePath $FilePath -WindowStyle Hidden -Wait -PassThru -ArgumentList $ArgumentList
        }
    }
    foreach ($code in @(0,1,2,10)) {
        ('param($Mode,$Language,$CallerSid,[switch]$NoPause)' + [Environment]::NewLine + 'exit ' + $code) | Set-Content -LiteralPath $handoffFixture -Encoding UTF8
        $handoffCode = & $module { param($Entry) Start-ElevatedInstaller -EntryPath $Entry -Language en -CallerSid 'S-1-5-21-1-1001' -NoPause } $handoffFixture
        Assert-Equal $handoffCode $code ('Preserve exit code through encoded handoff: ' + $code)
    }
    # A script the administrator window cannot start (moved folder, unmapped drive) is not a success.
    $missingCode = & $module { param($Entry) Start-ElevatedInstaller -EntryPath $Entry -Language en -CallerSid 'S-1-5-21-1-1001' -NoPause } (Join-Path $tempRoot 'moved folder\Install-ChatGPT.ps1')
    Assert-Equal $missingCode 3 'Unstartable elevated script returns 3'
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
    $env:ProgramData = $tempRoot
    $interactiveScenarios = @('WaitForAppExit','ReopenedDuringInstall','StillOpen')
    foreach ($scenario in @('Current','Update','Pending','SignatureFailure','DownloadFailure','ChangedAccount','Offline','MissingDependency','Elevation','ElevationStartFailure','ElevationClosed','PolicyFailure','UnknownFailure','FallbackOlder','FallbackNoDowngrade','FallbackSignatureFailure','Http404','Http403','WrappedTimeout','TransientTimeout','SocketDrop','SocketDropRepeated') + $interactiveScenarios) {
        Remove-Module Installer -Force
        $module = Import-Module $modulePath -Force -DisableNameChecking -PassThru
        & $module {
            param($Scenario)
            $script:Scenario = $Scenario
            $script:MutexName = 'Local\ChatGPTWindowsInstaller.Tests.' + $PID
            $script:InstallCalls = 0; $script:DownloadCalls = 0; $script:FeedCalls = 0; $script:ElevationCalls = 0; $script:ProcessPolls = 0
            function script:Get-CurrentUserSid { 'S-1-5-21-1-1001' }
            function script:Test-IsAdministrator { $script:Scenario -notlike 'Elevation*' }
            function script:Start-Sleep { param($Seconds) }
            function script:Get-RunningAppProcess {
                $script:ProcessPolls++
                # WaitForAppExit: open for two polls. ReopenedDuringInstall: reopened after the first install.
                if (($script:Scenario -eq 'WaitForAppExit' -and $script:ProcessPolls -le 2) -or ($script:Scenario -eq 'ReopenedDuringInstall' -and $script:ProcessPolls -eq 2)) { return @([pscustomobject]@{ ProcessName = 'ChatGPT' }) }
                return @()
            }
            function script:Get-SystemSnapshot {
                [pscustomobject]@{windowsVersion='10.0.26100.0';architecture='x64';availableDiskBytes=@(10GB);pendingReboot=$false;services=@();configuredPolicies=@();legacyAppDetected=$false}
            }
            function script:Get-RecentDeploymentErrors { @() }
            function script:New-ProtectedStagingDirectory {
                $directory = Join-Path $env:ProgramData ('ChatGPTWindowsInstaller-' + [guid]::NewGuid().ToString('N'))
                $null = New-Item -ItemType Directory -Path $directory
                return $directory
            }
            function script:Get-LatestRelease {
                param($Architecture)
                $script:FeedCalls++
                [pscustomobject]@{Version='26.915.4065.0';Architecture='x64';Uri='https://persistent.oaistatic.com/codex-app-prod/releases/26.915.4065.0/ChatGPT-x64.msix'}
            }
            function script:Get-InstalledPackage {
                # Registration completes on the first install unless ChatGPT stayed open (deferred).
                $registered = $script:InstallCalls -gt 0 -and $script:Scenario -notin @('Pending','StillOpen')
                if ($script:Scenario -eq 'ReopenedDuringInstall') { $registered = $script:InstallCalls -ge 2 }
                $version = if ($script:Scenario -in @('Current','FallbackNoDowngrade') -or $registered) { '26.915.4065.0' } else { '26.903.8094.0' }
                if ($script:Scenario -eq 'FallbackNoDowngrade') { $version = '26.912.1.0' }
                if ($script:Scenario -eq 'FallbackOlder' -and $script:InstallCalls -gt 0) { $version = '26.910.1.0' }
                [pscustomobject]@{Version=$version;Status='Ok'}
            }
            function script:Save-OfficialPackage {
                param($Release,$Destination,$ResumeState)
                $script:DownloadCalls++
                if ($script:Scenario -eq 'DownloadFailure') { throw 'DOWNLOAD_INCOMPLETE' }
                if ($script:Scenario -eq 'Http404') { [InstallerTestNetwork]::Fail(404) }
                if ($script:Scenario -eq 'Http403') { [InstallerTestNetwork]::Fail(403) }
                if ($script:Scenario -eq 'WrappedTimeout' -or ($script:Scenario -eq 'TransientTimeout' -and $script:DownloadCalls -eq 1)) { [InstallerTestNetwork]::Timeout() }
                if ($script:Scenario -eq 'SocketDropRepeated' -or ($script:Scenario -eq 'SocketDrop' -and $script:DownloadCalls -eq 1)) { throw (New-Object IO.IOException('Unable to read data from the transport connection.', (New-Object Net.Sockets.SocketException(10054)))) }
                if ($script:Scenario -in @('FallbackOlder','FallbackNoDowngrade','FallbackSignatureFailure') -and $Release.Uri -match '/releases/') { [InstallerTestNetwork]::Fail(404) }
                if ($script:DownloadCalls -gt 1 -and $script:Scenario -like 'Fallback*' -and $Release.Uri -ne 'https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix') { throw 'Wrong fallback source' }
                [IO.File]::WriteAllText($Destination,'mock-package')
            }
            function script:Confirm-OfficialPackage {
                param($Path,$Release,$WindowsVersion,[switch]$AllowVersionDifference)
                if ($script:Scenario -in @('SignatureFailure','FallbackSignatureFailure')) { throw 'PACKAGE_SIGNATURE_INVALID' }
                $version = if ($script:Scenario -in @('FallbackOlder','FallbackNoDowngrade')) { '26.910.1.0' } else { $Release.Version }
                if (-not $AllowVersionDifference -and $Release.Version -ne $version) { throw 'PACKAGE_VERSION_MISMATCH' }
                [pscustomobject]@{Metadata=[pscustomobject]@{Dependencies=@();Version=$version};Sha256=('A'*64);SignatureStatus='Valid'}
            }
            function script:Get-DependencyFindings {
                param($Metadata)
                if ($script:Scenario -eq 'MissingDependency') { New-Finding 'DEPENDENCY_MISSING' 'blocker' 'Missing' 'Use official installer.' }
            }
            function script:Add-AppxPackage {
                [CmdletBinding()]param($Path,[switch]$DeferRegistrationWhenPackagesAreInUse)
                $script:InstallCalls++
                if (-not $DeferRegistrationWhenPackagesAreInUse) { throw 'Test requires deferred registration' }
                if ($Path -notmatch 'ChatGPTWindowsInstaller-[a-f0-9]{32}[\\/]ChatGPT-x64\.msix$' -or -not (Test-Path -LiteralPath $Path)) { throw 'Windows must receive the existing staged copy' }
                if ($script:Scenario -eq 'PolicyFailure') { throw '0x80073D01' }
                if ($script:Scenario -eq 'UnknownFailure') { throw 'Private C:\Users\SecretName\data token=private 0xDEADBEEF' }
            }
            function script:Start-ElevatedInstaller {
                param($EntryPath,$Language,$CallerSid,[switch]$NoPause)
                $script:ElevationCalls++
                if ($script:Scenario -eq 'ElevationStartFailure') { return 3 }
                if ($script:Scenario -eq 'ElevationClosed') { return -1073741510 }
                return 10
            }
        } $scenario
        $handoffResult = [ref]$false
        $params = @{ Mode='Auto'; Language='en'; NoPause=($scenario -notin $interactiveScenarios); EntryPath=(Join-Path $root 'Install-ChatGPT.ps1'); Handoff=$handoffResult }
        if ($scenario -eq 'ChangedAccount') { $params.CallerSid='S-1-5-21-2-1002' }
        if ($scenario -eq 'Offline') { $params.Mode='Diagnose'; $params.Offline=$true }
        $result = Invoke-ChatGPTInstaller @params 6>$null
        $counts = & $module { @($script:InstallCalls, $script:DownloadCalls, $script:FeedCalls, $script:ElevationCalls, $script:ProcessPolls) }
        # Exit status, installs, downloads, feed checks, elevations, ChatGPT process checks.
        $expected = switch ($scenario) {
            'Current' { @(0,0,0,1,0,0) }
            'Update' { @(0,1,1,1,0,0) }
            'Pending' { @(10,1,1,1,0,0) }
            'SignatureFailure' { @(1,0,1,1,0,0) }
            'DownloadFailure' { @(1,0,1,1,0,0) }
            'ChangedAccount' { @(2,0,0,0,0,0) }
            'Offline' { @(0,0,0,0,0,0) }
            'MissingDependency' { @(2,0,1,1,0,0) }
            'Elevation' { @(10,0,0,1,1,0) }
            'ElevationStartFailure' { @(3,0,0,1,1,0) }
            'ElevationClosed' { @(1,0,0,1,1,0) }
            'PolicyFailure' { @(1,1,1,1,0,0) }
            'UnknownFailure' { @(1,1,1,1,0,0) }
            'FallbackOlder' { @(0,1,2,1,0,0) }
            'FallbackNoDowngrade' { @(0,0,2,1,0,0) }
            'FallbackSignatureFailure' { @(1,0,2,1,0,0) }
            'Http404' { @(1,0,2,1,0,0) }
            'Http403' { @(1,0,1,1,0,0) }
            'WrappedTimeout' { @(1,0,5,1,0,0) }
            'TransientTimeout' { @(0,1,2,1,0,0) }
            'SocketDrop' { @(0,1,2,1,0,0) }
            'SocketDropRepeated' { @(1,0,5,1,0,0) }
            'WaitForAppExit' { @(0,1,1,1,0,3) }
            'ReopenedDuringInstall' { @(0,2,1,1,0,3) }
            'StillOpen' { @(10,3,1,1,0,3) }
        }
        Assert-Equal $result $expected[0] ($scenario + ' exit status')
        for ($i=0; $i -lt 5; $i++) { Assert-Equal $counts[$i] $expected[$i+1] ($scenario + ' side effects ' + $i) }
        # Only a completed handoff suppresses the launcher's pause; failures must stay visible.
        Assert-Equal $handoffResult.Value ($scenario -eq 'Elevation') ($scenario + ' handoff')
        if ($scenario -in @('FallbackOlder','FallbackNoDowngrade','Http404','Http403','WrappedTimeout','SocketDropRepeated','ElevationStartFailure','ElevationClosed')) {
            $latestReport = Get-ChildItem -LiteralPath (Join-Path $tempRoot 'ChatGPTWindowsInstaller\reports') -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $report = Get-Content -LiteralPath $latestReport.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $expectedCode = switch ($scenario) {
                'Http404' { 'HTTP_404' }; 'Http403' { 'HTTP_403' }; 'WrappedTimeout' { '0x80072EE2' }; 'SocketDropRepeated' { '0x80072EFD' }
                'ElevationStartFailure' { 'ELEVATED_START_FAILED' }; 'ElevationClosed' { 'ELEVATED_WINDOW_CLOSED' }
                default { 'RELEASE_CHANNEL_DIFFERENCE' }
            }
            Assert-Equal ($expectedCode -in $report.findings.code) $true ($scenario + ' actionable finding')
            if ($scenario -like 'Fallback*') {
                Assert-Equal $report.packageVersion '26.910.1.0' 'Report actual signed package version'
                Assert-Equal $report.latestVersion '26.915.4065.0' 'Retain advertised version separately'
            }
        }
    }
    foreach ($reportFile in Get-ChildItem -LiteralPath (Join-Path $tempRoot 'ChatGPTWindowsInstaller\reports') -Filter '*.json') {
        $contents = Get-Content -LiteralPath $reportFile.FullName -Raw -Encoding UTF8
        Assert-Equal ($contents -match 'SecretName|token=private|S-1-5-21-|C:\\\\Users\\\\|proxy\.invalid|user:secret|Private proxy secret') $false 'No raw exception, username, SID, user path or proxy credentials in report'
        $null = $contents | ConvertFrom-Json -ErrorAction Stop
    }
    Assert-Equal (@(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'ChatGPTWindowsInstaller\reports') -File).Count -le 40) $true 'Reports are limited to the newest 20 runs'

    # Real download code with a scripted server: drop the connection, then resume with If-Range.
    Remove-Module Installer -Force
    $module = Import-Module $modulePath -Force -DisableNameChecking -PassThru
    $packageBytes = New-Object byte[] 4096
    for ($i = 0; $i -lt $packageBytes.Length; $i++) { $packageBytes[$i] = [byte]($i % 251) }
    & $module {
        param([byte[]]$Bytes)
        $script:PackageBytes = $Bytes
        $script:FailAt = 1500
        $script:ResponseLog = New-Object Collections.ArrayList
        function script:New-TestResponse {
            param([int]$Status, [long]$Length, [hashtable]$Headers, $Stream)
            $response = [pscustomobject]@{ StatusCode = $Status; ContentLength = $Length; Headers = $Headers; Stream = $Stream }
            $response | Add-Member -MemberType ScriptMethod -Name GetResponseStream -Value { $this.Stream }
            $response | Add-Member -MemberType ScriptMethod -Name Close -Value { }
            return $response
        }
        function script:Get-OfficialResponse {
            param([string]$Uri, [long]$Offset = 0, [string]$Validator)
            [void]$script:ResponseLog.Add(('{0}|{1}' -f $Offset, $Validator))
            $size = $script:PackageBytes.Length
            if ($Offset -eq 0) { return New-TestResponse 200 $size @{ ETag = '"v1"' } ([InstallerTestStream]::new($script:PackageBytes, 0, $script:FailAt)) }
            if ($Validator -ceq '"v1"') { return New-TestResponse 206 ($size - $Offset) @{ ETag = '"v1"'; 'Content-Range' = ('bytes {0}-{1}/{2}' -f $Offset, ($size - 1), $size) } ([InstallerTestStream]::new($script:PackageBytes, $Offset, -1)) }
            # The file changed on the server: If-Range yields the whole new file.
            return New-TestResponse 200 $size @{ ETag = '"v2"' } ([InstallerTestStream]::new($script:PackageBytes, 0, -1))
        }
    } $packageBytes
    $resumeDirectory = Join-Path $tempRoot 'resume'
    $null = New-Item -ItemType Directory -Path $resumeDirectory
    $resumeTarget = Join-Path $resumeDirectory 'ChatGPT-x64.msix'
    $resumeRelease = [pscustomobject]@{ Uri = 'https://persistent.oaistatic.com/codex-app-prod/releases/26.915.4065.0/ChatGPT-x64.msix' }
    $resumeState = @{}
    $saveScript = { param($Release, $Destination, $State) Save-OfficialPackage $Release $Destination $State }
    Assert-Throws { & $module $saveScript $resumeRelease $resumeTarget $resumeState } 'transport connection' 'Dropped download reports the transport error'
    Assert-Equal (Get-Item -LiteralPath $resumeTarget).Length 1500 'Partial download is kept for resuming'
    Assert-Equal $resumeState['Validator'] '"v1"' 'Strong ETag is kept for If-Range'
    & $module $saveScript $resumeRelease $resumeTarget $resumeState
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($resumeTarget))) ([Convert]::ToBase64String($packageBytes)) 'Resumed file matches the original bytes'
    Assert-Equal ((& $module { $script:ResponseLog }) -join ',') '0|,1500|"v1"' 'Second request resumes at the partial length with If-Range'
    [IO.File]::WriteAllBytes($resumeTarget, [byte[]](7, 7, 7))
    $resumeState['Validator'] = '"stale"'
    & $module $saveScript $resumeRelease $resumeTarget $resumeState
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($resumeTarget))) ([Convert]::ToBase64String($packageBytes)) 'Changed server file replaces the partial file'
    Assert-Equal $resumeState['Validator'] '"v2"' 'New validator is kept after a full response'

    # Leftovers from interrupted runs: only this tool's package names, in old run folders, are removed.
    $staleRoot = Join-Path $tempRoot 'stale-cache'
    $staleTime = (Get-Date).AddDays(-2)
    $staleFolders = @{}
    foreach ($folder in @(@(('a' * 32), 'ChatGPT-x64.msix', $staleTime), @(('b' * 32), 'ChatGPT-arm64.msix|keep.txt', $staleTime), @(('c' * 32), 'ChatGPT-x64.msix', (Get-Date)), @('not-a-run-folder', 'ChatGPT-x64.msix', $staleTime))) {
        $directory = Join-Path $staleRoot $folder[0]
        $null = New-Item -ItemType Directory -Path $directory -Force
        foreach ($name in $folder[1].Split('|')) { 'fixture' | Set-Content -LiteralPath (Join-Path $directory $name) }
        (Get-Item -LiteralPath $directory).LastWriteTime = $folder[2]
        $staleFolders[$folder[0]] = $directory
    }
    & $module { param($Root) Clear-StaleInstallerFiles $Root $null } $staleRoot
    Assert-Equal (Test-Path -LiteralPath $staleFolders[('a' * 32)]) $false 'Stale run folder with only a package is removed'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $staleFolders[('b' * 32)] 'ChatGPT-arm64.msix')) $false 'Stale package is removed'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $staleFolders[('b' * 32)] 'keep.txt')) $true 'Unknown files are never removed'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $staleFolders[('c' * 32)] 'ChatGPT-x64.msix')) $true 'Recent run folder is untouched'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $staleFolders['not-a-run-folder'] 'ChatGPT-x64.msix')) $true 'Foreign folder is untouched'
    if (& $module { Test-IsAdministrator }) {
        # Needs elevation to create the real protected staging folder (CI runners are elevated).
        $stagingTestRoot = Join-Path $tempRoot 'stale-staging'
        $null = New-Item -ItemType Directory -Path $stagingTestRoot
        $env:ProgramData = $stagingTestRoot
        $protectedFolder = & $module { New-ProtectedStagingDirectory }
        'fixture' | Set-Content -LiteralPath (Join-Path $protectedFolder 'ChatGPT-x64.msix')
        (Get-Item -LiteralPath $protectedFolder).LastWriteTime = $staleTime
        & $module { param($Root) Clear-StaleInstallerFiles $null $Root } $stagingTestRoot
        Assert-Equal (Test-Path -LiteralPath $protectedFolder) $false 'Stale protected staging folder is removed'
        $env:ProgramData = $tempRoot
    }

    # Report rotation keeps the newest 40 files (20 runs).
    $rotationRoot = Join-Path $tempRoot 'rotation'
    $null = New-Item -ItemType Directory -Path $rotationRoot
    for ($i = 0; $i -lt 45; $i++) {
        $oldReport = Join-Path $rotationRoot ('report-20260101-0000{0:D2}-abcdef.txt' -f $i)
        'old' | Set-Content -LiteralPath $oldReport
        (Get-Item -LiteralPath $oldReport).LastWriteTime = (Get-Date).AddDays(-10).AddMinutes($i)
    }
    'unrelated' | Set-Content -LiteralPath (Join-Path $rotationRoot 'notes.txt')
    $rotationReport = [ordered]@{ outcome = 'Current'; generatedUtc = 'test'; system = $null; latestVersion = '1.0.0.0'; packageVersion = $null; installedVersionAfter = $null; findings = @() }
    $newReport = & $module { param($Report, $Directory) Write-Report $Report $Directory } $rotationReport $rotationRoot
    Assert-Equal @(Get-ChildItem -LiteralPath $rotationRoot -Filter 'report-*').Count 40 'Old reports are rotated'
    Assert-Equal (Test-Path -LiteralPath $newReport) $true 'Newest report is kept'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $rotationRoot 'report-20260101-000000-abcdef.txt')) $false 'Oldest report is removed'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $rotationRoot 'notes.txt')) $true 'Unrelated files are kept'

    # The real process check must be quick and quiet: the elevated window polls it.
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $null = & $module { @(Get-RunningAppProcess).Count }
    Assert-Equal ($timer.Elapsed.TotalSeconds -lt 10) $true 'ChatGPT process check completes'

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        # A window started with "Run as administrator" holds a lock a standard window cannot open.
        $deniedName = 'Local\ChatGPTWindowsInstaller.Tests.Denied.' + $PID
        $mutexSecurity = New-Object Security.AccessControl.MutexSecurity
        $mutexSecurity.AddAccessRule((New-Object Security.AccessControl.MutexAccessRule([Security.Principal.WindowsIdentity]::GetCurrent().User, [Security.AccessControl.MutexRights]::FullControl, [Security.AccessControl.AccessControlType]::Deny)))
        $createdNew = $false
        $deniedMutex = [Threading.Mutex]::new($false, $deniedName, [ref]$createdNew, $mutexSecurity)
        try {
            & $module { param($Name) $script:MutexName = $Name } $deniedName
            $deniedResult = Invoke-ChatGPTInstaller -Mode Auto -Language en -NoPause -EntryPath (Join-Path $root 'Install-ChatGPT.ps1') 6>$null
            Assert-Equal $deniedResult 1 'Inaccessible lock stops the second window'
            $latestReport = Get-ChildItem -LiteralPath (Join-Path $tempRoot 'ChatGPTWindowsInstaller\reports') -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $report = Get-Content -LiteralPath $latestReport.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-Equal ('ANOTHER_INSTANCE' -in $report.findings.code) $true 'Inaccessible lock is reported as another running copy'
        } finally { $deniedMutex.Dispose() }
    }
}
finally {
    $env:LOCALAPPDATA = $oldLocal
    $env:ProgramData = $oldProgramData
    Remove-Module Installer -Force -ErrorAction SilentlyContinue
    # Delete only the test-owned, resolved temporary folder.
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'chatgpt-installer-tests-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host ("PASS: {0} assertions. No real applications installed, removed, or updated." -f $script:Passed) -ForegroundColor Green
