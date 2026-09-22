#Requires -Version 5.1
Set-StrictMode -Version 2.0
$script:ToolVersion = '1.0.3'
$script:PackageIdentity = 'OpenAI.Codex'
$script:PackagePublisher = 'CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B'
$script:FeedUri = 'https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json'
$script:ReleaseRoot = 'https://persistent.oaistatic.com/codex-app-prod/releases/'
$script:Language = 'en'
$script:MutexName = 'Local\ChatGPTWindowsInstaller'
$script:ErrorCatalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'errors.json') -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-Text {
    param([string]$English, [string]$Russian)
    if ($script:Language -eq 'ru') { return $Russian }
    return $English
}

function Write-Step {
    param([string]$English, [string]$Russian, [ConsoleColor]$Color = 'Cyan')
    Write-Host (Get-Text $English $Russian) -ForegroundColor $Color
}

function Get-NativeArchitecture {
    # PROCESSOR_ARCHITECTURE may describe an emulated process, not the computer.
    $value = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE', 'Machine')
    if (-not $value) { $value = $env:PROCESSOR_ARCHITEW6432 }
    if (-not $value) { $value = $env:PROCESSOR_ARCHITECTURE }
    switch ($value) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default { return 'unsupported' }
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CurrentUserSid {
    return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function New-Finding {
    param([string]$Code, [string]$Severity, [string]$Summary, [string]$Action)
    return [pscustomobject][ordered]@{ code = $Code; severity = $Severity; summary = $Summary; action = $Action }
}

function Get-ErrorAdvice {
    param([string]$Code)
    $entry = $script:ErrorCatalog | Where-Object code -eq $Code | Select-Object -First 1
    if (-not $entry) {
        return New-Finding $Code 'error' (Get-Text 'The failure is not in this version of the error catalog.' 'Причина не распознана этой версией справочника ошибок.') (Get-Text 'Keep the error code. Check AppXDeploymentServer in Event Viewer or contact support. No destructive repair was attempted.' 'Сохраните код. Проверьте AppXDeploymentServer в журнале событий или обратитесь в поддержку. Разрушающие исправления не выполнялись.')
    }
    $advice = switch ($entry.category) {
        'AdminRequired' { Get-Text 'Run Start.cmd and accept the Windows administrator prompt. If you lack administrator access, ask the device administrator.' 'Запустите Start.cmd и подтвердите запрос администратора Windows. Если прав нет, обратитесь к администратору.' }
        'AppInUse' { Get-Text 'Close ChatGPT normally, including its tray icon, then run Start.cmd again. Save active work first.' 'Закройте ChatGPT, включая значок возле часов, затем повторите Start.cmd. Сначала сохраните работу.' }
        'DiskSpace' { Get-Text 'Free space on both the Windows drive and the download drive, then retry. This tool never deletes personal files.' 'Освободите место на диске Windows и диске загрузки, затем повторите. Скрипт не удаляет личные файлы.' }
        'Dependency' { Get-Text 'Review the dependency findings and Windows deployment events. Obtain dependencies only from Microsoft or your IT administrator; do not remove conflicting packages blindly.' 'Проверьте список зависимостей и журнал установки Windows. Получайте зависимости у Microsoft или администратора; не удаляйте конфликтующие пакеты наугад.' }
        'Network' { Get-Text 'Check connectivity, proxy authentication, and access to persistent.oaistatic.com. Retry on a working permitted network.' 'Проверьте сеть, авторизацию прокси и доступ к persistent.oaistatic.com. Повторите в работающей разрешённой сети.' }
        'Dns' { Get-Text 'Check that DNS can resolve persistent.oaistatic.com. Ask the network administrator if filtering is intentional.' 'Проверьте разрешение имени persistent.oaistatic.com в DNS. При намеренной фильтрации обратитесь к администратору сети.' }
        'Tls' { Get-Text 'Check Windows date/time, Windows Update, certificate trust and the corporate proxy. Do not disable certificate validation.' 'Проверьте дату и время, обновления Windows, доверие сертификатам и корпоративный прокси. Не отключайте проверку сертификатов.' }
        'Signature' { Get-Text 'The package was not installed. Check date/time and Windows trust updates, then retry the official download. Never bypass signature checks.' 'Пакет не установлен. Проверьте время и обновления доверенных сертификатов Windows, затем повторите загрузку. Не обходите проверку подписи.' }
        'PackageInvalid' { Get-Text 'Retry a fresh official download. If it repeats, inspect disk health and Windows deployment events.' 'Повторите загрузку официального пакета. Если сбой повторяется, проверьте диск и журнал установки Windows.' }
        'Policy' { Get-Text 'Ask the device administrator to approve deployment. This tool does not change Group Policy, AppLocker, WDAC, or sideloading restrictions.' 'Попросите администратора разрешить установку. Скрипт не меняет групповые политики, AppLocker, WDAC и ограничения установки.' }
        'AccessDenied' { Get-Text 'Confirm administrator approval, then check device policy and security-software events. Keep antivirus enabled.' 'Подтвердите права администратора, проверьте политики и события защитного ПО. Оставьте антивирус включённым.' }
        'Compatibility' { Get-Text 'Install applicable Windows updates and check the package minimum Windows version. Managed devices may need IT assistance.' 'Установите доступные обновления Windows и проверьте минимальную версию для пакета. На управляемом ПК может понадобиться помощь ИТ.' }
        'Architecture' { Get-Text 'Use the official package matching the native processor architecture. 32-bit Windows is not supported by this tool.' 'Используйте официальный пакет для архитектуры процессора. 32-разрядная Windows этим инструментом не поддерживается.' }
        'Cancelled' { Get-Text 'Run the tool again when ready and approve the Windows prompt if installation is intended.' 'Повторите запуск, когда будете готовы, и подтвердите запрос Windows для установки.' }
        'WindowsRepair' { Get-Text 'Install Windows updates, restart, and ask Windows support or IT to assess system repair. This tool does not automatically run DISM/SFC or reset the package repository.' 'Обновите Windows, перезагрузитесь и обратитесь в поддержку Windows или ИТ для восстановления системы. Скрипт не запускает DISM/SFC и не сбрасывает хранилище пакетов автоматически.' }
        'FirewallService' { Get-Text 'Ask the administrator to restore normal Windows Firewall service operation; do not disable the firewall.' 'Попросите администратора восстановить штатную работу службы брандмауэра; не отключайте брандмауэр.' }
        'ServiceDisabled' { Get-Text 'Check the disabled services listed in the report with the device administrator. The tool does not override managed service settings.' 'Проверьте отключённые службы из отчёта с администратором. Скрипт не переопределяет настройки управляемых служб.' }
        'ServiceConflict' { Get-Text 'Ask the app vendor or IT to resolve the service/version conflict. Do not delete system services.' 'Обратитесь к разработчику приложения или ИТ для устранения конфликта служб и версий. Не удаляйте системные службы.' }
        'OtherUser' { Get-Text 'Ask other signed-in users to save work and sign out, then retry. The tool does not sign anyone out.' 'Попросите других пользователей сохранить работу и выйти из Windows, затем повторите. Скрипт не завершает чужие сеансы.' }
        'SmartScreen' { Get-Text 'Check connectivity and Windows security events, then retry the official package. Keep SmartScreen enabled.' 'Проверьте сеть и события безопасности Windows, затем повторите с официальным пакетом. Оставьте SmartScreen включённым.' }
        'Volume' { Get-Text 'Check the target drive availability and health. Ask IT before modifying package volumes.' 'Проверьте доступность и состояние диска. Перед изменением дисков с пакетами обратитесь в ИТ.' }
        'AppData' { Get-Text 'Close the app normally and restart Windows if needed. Do not delete app data without a backup.' 'Закройте приложение, при необходимости перезагрузите Windows. Не удаляйте данные приложения без резервной копии.' }
        'Busy' { Get-Text 'Let the current Windows/Store update finish and retry. No installer processes will be killed.' 'Дождитесь завершения обновления Windows или Store и повторите. Процессы установщиков не завершаются принудительно.' }
        'NewerInstalled' { Get-Text 'Keep the newer installed version. Downgrades are disabled.' 'Используйте установленную более новую версию. Понижение версии отключено.' }
        'AlreadyInstalled' { Get-Text 'Check the installed version and package status. Use the official installer if registration is inconsistent.' 'Проверьте версию и состояние пакета. При проблемах регистрации используйте официальный установщик.' }
        'PackageMissing' { Get-Text 'Run Start.cmd to obtain a complete official package. If a dependency is missing, check Windows deployment events.' 'Запустите Start.cmd для получения полного официального пакета. Если отсутствует зависимость, проверьте журнал установки Windows.' }
        default { Get-Text 'Review the recent error codes and AppXDeploymentServer events. Restart if an update is pending, or ask Windows support.' 'Проверьте последние коды и события AppXDeploymentServer. При ожидающей перезагрузке выполните её или обратитесь в поддержку Windows.' }
    }
    return New-Finding $entry.code 'error' $entry.($script:Language) $advice
}

function Get-ErrorCodes {
    param([string]$Text)
    return @([regex]::Matches($Text, '(?i)\b0x[0-9a-f]{8}\b') | ForEach-Object { '0x' + $_.Value.Substring(2).ToUpperInvariant() } | Select-Object -Unique)
}

function Get-ExceptionCode {
    param($ErrorRecord)
    $parts = @([string]$ErrorRecord)
    $exception = $ErrorRecord.Exception
    for ($depth = 0; $exception -and $depth -lt 8; $depth++) {
        if ($exception -is [ComponentModel.Win32Exception] -and $exception.NativeErrorCode -eq 1223) { return '0x800704C7' }
        $parts += $exception.Message
        $parts += ('0x{0:X8}' -f $exception.HResult)
        $exception = $exception.InnerException
    }
    $codes = @(Get-ErrorCodes ($parts -join ' '))
    $specific = @($codes | Where-Object { $_ -ne '0x80073CF6' -and $_ -ne '0x80004005' -and $_ -in $script:ErrorCatalog.code })
    if ($specific.Count) { return $specific[0] }
    if ($codes.Count) { return $codes[0] }
    return 'UNCLASSIFIED'
}

function Get-NetworkException {
    param($ErrorRecord)
    # .NET calls in Windows PowerShell wrap WebException in MethodInvocationException.
    $exception = $ErrorRecord.Exception
    for ($depth = 0; $exception -and $depth -lt 8; $depth++) {
        if ($exception -is [Net.WebException]) { return $exception }
        $exception = $exception.InnerException
    }
    return $null
}

function Test-TransientNetworkFailure {
    param($ErrorRecord)
    # A connection dropped mid-download surfaces as IOException wrapping SocketException, not WebException.
    $exception = $ErrorRecord.Exception
    for ($depth = 0; $exception -and $depth -lt 8; $depth++) {
        if ($exception -is [Net.WebException]) { return $exception.Status -in @([Net.WebExceptionStatus]::Timeout, [Net.WebExceptionStatus]::ConnectionClosed, [Net.WebExceptionStatus]::ReceiveFailure, [Net.WebExceptionStatus]::ConnectFailure, [Net.WebExceptionStatus]::KeepAliveFailure) }
        if ($exception -is [Net.Sockets.SocketException]) { return $true }
        $exception = $exception.InnerException
    }
    return $false
}

function ConvertTo-Release {
    param($Feed, [ValidateSet('x64', 'arm64')][string]$Architecture)
    if (-not $Feed -or -not ($Feed.PSObject.Properties.Name -contains 'schemaVersion') -or $Feed.schemaVersion -ne 1) { throw 'FEED_FORMAT_CHANGED' }
    foreach ($name in @('buildVersion', 'packageIdentity', 'storeProductId')) {
        if (-not ($Feed.PSObject.Properties.Name -contains $name)) { throw 'FEED_FORMAT_CHANGED' }
    }
    if ($Feed.packageIdentity -cne $script:PackageIdentity -or $Feed.storeProductId -cne '9PLM9XGG6VKS') { throw 'FEED_IDENTITY_MISMATCH' }
    $versionText = [string]$Feed.buildVersion
    if ($versionText -cnotmatch '^\d{1,5}\.\d{1,5}\.\d{1,5}\.\d{1,5}$') { throw 'FEED_VERSION_INVALID' }
    $version = [version]$versionText
    foreach ($part in @($version.Major, $version.Minor, $version.Build, $version.Revision)) { if ($part -gt 65535) { throw 'FEED_VERSION_INVALID' } }
    return [pscustomobject]@{
        Version = $version.ToString(); Architecture = $Architecture
        Uri = $script:ReleaseRoot + $version.ToString() + '/ChatGPT-' + $Architecture + '.msix'
    }
}

function Assert-OfficialUri {
    param([string]$Uri)
    $parsed = $null
    if (-not [uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$parsed)) { throw 'UNTRUSTED_URL' }
    if ($parsed.Scheme -cne 'https' -or $parsed.Host -cne 'persistent.oaistatic.com' -or -not $parsed.IsDefaultPort -or $parsed.UserInfo -or $parsed.Query -or $parsed.Fragment) { throw 'UNTRUSTED_URL' }
    $validPath = $parsed.AbsolutePath -ceq '/codex-app-prod/windows-store-update.json' -or $parsed.AbsolutePath -cmatch '^/codex-app-prod/releases/\d+\.\d+\.\d+\.\d+/ChatGPT-(x64|arm64)\.msix$' -or $parsed.AbsolutePath -cmatch '^/codex-app-prod/ChatGPT-(x64|arm64)\.msix$'
    if (-not $validPath) { throw 'UNTRUSTED_URL' }
}

function Get-OfficialResponse {
    param([string]$Uri, [long]$Offset = 0, [string]$Validator)
    Assert-OfficialUri $Uri
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($Uri)
    $request.AllowAutoRedirect = $false
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 60000
    $request.UserAgent = 'ChatGPT-Windows-Installer/' + $script:ToolVersion
    if ($Offset -gt 0) {
        # If-Range makes the server resend the whole file when it changed since the interrupted attempt.
        if (-not $Validator) { throw 'DOWNLOAD_RANGE_INVALID' }
        $request.AddRange($Offset)
        $request.Headers.Add('If-Range', $Validator)
    }
    # Use Windows' configured proxy; never print its address or credentials.
    $response = $request.GetResponse()
    $status = [int]$response.StatusCode
    if ($status -ne 200 -and -not ($Offset -gt 0 -and $status -eq 206)) { $response.Close(); throw 'UNEXPECTED_HTTP_STATUS' }
    return $response
}

function Get-LatestRelease {
    param([string]$Architecture)
    $response = Get-OfficialResponse $script:FeedUri
    try {
        if ($response.ContentLength -gt 16384) { throw 'FEED_TOO_LARGE' }
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        try {
            $buffer = New-Object char[] 16385
            $length = $reader.ReadBlock($buffer, 0, $buffer.Length)
            if ($length -gt 16384) { throw 'FEED_TOO_LARGE' }
            $json = New-Object string($buffer, 0, $length)
        } finally { $reader.Dispose() }
        return ConvertTo-Release ($json | ConvertFrom-Json -ErrorAction Stop) $Architecture
    } finally { $response.Close() }
}

function Get-InstalledPackage {
    return Get-AppxPackage -Name $script:PackageIdentity -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1
}

function Get-UpdateDecision {
    param([AllowNull()]$Installed, [string]$AvailableVersion)
    if (-not $Installed) { return 'Install' }
    if ([string]$Installed.Status -ne 'Ok') { return 'NeedsRepair' }
    if ([version]$Installed.Version -gt [version]$AvailableVersion) { return 'NewerInstalled' }
    if ([version]$Installed.Version -eq [version]$AvailableVersion) { return 'Current' }
    return 'Update'
}

function Get-SystemSnapshot {
    $windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build = [int]$windows.CurrentBuildNumber
    $revision = 0
    if ($windows.PSObject.Properties.Name -contains 'UBR') { $revision = [int]$windows.UBR }
    $installed = Get-InstalledPackage
    $services = @()
    foreach ($name in @('AppXSvc', 'ClipSVC', 'InstallService', 'AppReadiness', 'BITS', 'wuauserv', 'mpssvc')) {
        try {
            $service = Get-Service -Name $name -ErrorAction Stop
            $services += [pscustomobject]@{ name = $name; status = [string]$service.Status; startType = [string]$service.StartType }
        } catch { $services += [pscustomobject]@{ name = $name; status = 'Unknown'; startType = 'Unknown' } }
    }
    $geo = 'Unknown'
    try { $geo = (Get-WinHomeLocation -ErrorAction Stop).HomeLocation } catch { }
    $policies = @()
    foreach ($check in @(
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx', 'BlockNonAdminUserInstall'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx', 'AllowAllTrustedApps'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore', 'RemoveWindowsStore'),
        @('HKCU:\SOFTWARE\Policies\Microsoft\WindowsStore', 'RemoveWindowsStore')
    )) {
        $property = Get-ItemProperty -Path $check[0] -Name $check[1] -ErrorAction SilentlyContinue
        if ($null -ne $property) { $policies += [pscustomobject]@{ name = $check[1]; value = $property.($check[1]) } }
    }
    $reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    $freeBytes = @()
    foreach ($root in @([IO.Path]::GetPathRoot($env:SystemRoot), [IO.Path]::GetPathRoot($env:LOCALAPPDATA)) | Select-Object -Unique) {
        try { $freeBytes += (New-Object IO.DriveInfo($root)).AvailableFreeSpace } catch { }
    }
    $legacyFound = $false
    try { $legacyFound = @((Get-AppxPackage -Name 'OpenAI.ChatGPT-Desktop' -ErrorAction Stop)).Count -gt 0 } catch { }
    return [pscustomobject][ordered]@{
        windowsVersion = "10.0.$build.$revision"; architecture = Get-NativeArchitecture
        administrator = Test-IsAdministrator; powerShellVersion = $PSVersionTable.PSVersion.ToString()
        installedVersion = $(if ($installed) { [string]$installed.Version } else { $null })
        installedStatus = $(if ($installed) { [string]$installed.Status } else { $null })
        legacyAppDetected = $legacyFound; windowsHomeRegion = [string]$geo
        pendingReboot = [bool]$reboot; availableDiskBytes = $freeBytes
        services = $services; configuredPolicies = $policies
    }
}

function Get-PreflightFindings {
    param($Snapshot)
    if ($Snapshot.architecture -notin @('x64', 'arm64')) {
        New-Finding 'UNSUPPORTED_ARCHITECTURE' 'blocker' (Get-Text '64-bit Windows on x64 or ARM64 is required.' 'Требуется 64-разрядная Windows на x64 или ARM64.') (Get-Text 'Use a supported computer or ChatGPT in a browser where available.' 'Используйте совместимый компьютер или ChatGPT в браузере, где сервис доступен.')
    }
    if ([version]$Snapshot.windowsVersion -lt [version]'10.0.19041.0') {
        New-Finding 'WINDOWS_TOO_OLD' 'blocker' (Get-Text 'This installer requires Windows build 19041 or later. The downloaded app may require a newer build.' 'Скрипт требует сборку Windows 19041 или новее. Загруженное приложение может требовать более новую сборку.') (Get-Text 'Update Windows, then retry.' 'Обновите Windows и повторите.')
    }
    if (@($Snapshot.availableDiskBytes | Where-Object { $_ -lt 3GB }).Count -gt 0) {
        New-Finding 'LOW_DISK_SPACE' 'blocker' (Get-Text 'Less than 3 GB is available on a required drive.' 'На необходимом диске свободно менее 3 ГБ.') (Get-Text 'Free disk space and retry. The full package also receives a size-based space check.' 'Освободите место и повторите. Перед загрузкой также проверяется место с учётом размера пакета.')
    }
    if ($Snapshot.pendingReboot) {
        New-Finding 'REBOOT_PENDING' 'warning' (Get-Text 'Windows reports a pending restart.' 'Windows ожидает перезагрузки.') (Get-Text 'If installation fails, save work and restart Windows before retrying.' 'Если установка не проходит, сохраните работу, перезагрузите Windows и повторите.')
    }
    foreach ($service in $Snapshot.services | Where-Object startType -eq 'Disabled') {
        New-Finding ('SERVICE_DISABLED_' + $service.name) 'warning' (Get-Text ('Service disabled: ' + $service.name) ('Отключена служба: ' + $service.name)) (Get-Text 'Ask the device administrator whether this is intentional. Disabled Store services may affect Store delivery but do not always block direct MSIX installation.' 'Уточните у администратора, намеренно ли это сделано. Отключённые службы Store могут мешать магазину, но не всегда блокируют прямую установку MSIX.')
    }
    if ($Snapshot.configuredPolicies.Count -gt 0) {
        New-Finding 'DEVICE_POLICIES_PRESENT' 'info' (Get-Text 'Store or AppX policies are configured.' 'Обнаружены политики Store или AppX.') (Get-Text 'Their presence alone does not prove a block. Check their values with IT if deployment is denied.' 'Наличие политики ещё не означает запрет. При отказе установки уточните её значения у ИТ.')
    }
    if ($Snapshot.legacyAppDetected) {
        New-Finding 'LEGACY_APP_DETECTED' 'info' (Get-Text 'The separate legacy ChatGPT Windows app is also installed.' 'Также установлено прежнее отдельное приложение ChatGPT для Windows.') (Get-Text 'This tool installs the current ChatGPT desktop app (OpenAI.Codex). The legacy app is left installed.' 'Скрипт устанавливает нынешнее приложение ChatGPT (OpenAI.Codex). Прежнее приложение остаётся установленным.')
    }
    New-Finding 'REGION_CONTEXT' 'info' (Get-Text 'Windows region is not proof of physical location, citizenship, or OpenAI account eligibility.' 'Регион Windows не доказывает местоположение, гражданство или доступность аккаунта OpenAI.') (Get-Text 'After a move, review your real Windows and Microsoft account country. Service availability and installation are separate; this tool does not change regions or determine account eligibility.' 'После переезда проверьте фактическую страну в Windows и аккаунте Microsoft. Установка и доступ к сервису — разные вопросы; скрипт не меняет регион и не определяет доступность аккаунта.')
}

function Get-RecentDeploymentErrors {
    $events = @()
    try {
        $records = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'; StartTime = (Get-Date).AddDays(-7); Level = 2 } -MaxEvents 200 -ErrorAction Stop
        foreach ($record in $records) {
            if ($record.Message -notmatch 'OpenAI\.(Codex|ChatGPT-Desktop)') { continue }
            $codes = @(Get-ErrorCodes $record.Message)
            if ($codes.Count) { $events += [pscustomobject]@{ timeUtc = $record.TimeCreated.ToUniversalTime().ToString('o'); eventId = $record.Id; codes = $codes } }
            if ($events.Count -ge 10) { break }
        }
    } catch { }
    # Raw event messages contain paths and SIDs: intentionally never return them.
    return $events
}

function Save-OfficialPackage {
    param($Release, [string]$Destination, [hashtable]$ResumeState)
    # Resume only this run's partial file, from the same URL, guarded by the server's validator.
    [long]$offset = 0
    if ($ResumeState -and $ResumeState['Uri'] -ceq $Release.Uri -and $ResumeState['Validator'] -and (Test-Path -LiteralPath $Destination)) {
        $offset = (Get-Item -LiteralPath $Destination).Length
        if ($offset -ge [long]$ResumeState['Size']) { $offset = 0 }
    }
    $validator = $null
    if ($offset -gt 0) { $validator = $ResumeState['Validator'] }
    $response = Get-OfficialResponse $Release.Uri $offset $validator
    try {
        $mode = [IO.FileMode]::Create
        if ($offset -gt 0 -and [int]$response.StatusCode -eq 206) {
            $size = [long]$ResumeState['Size']
            $expectedRange = 'bytes ' + $offset + '-' + ($size - 1) + '/' + $size
            if ([string]$response.Headers['Content-Range'] -cne $expectedRange -or $response.ContentLength -ne $size - $offset) { throw 'DOWNLOAD_RANGE_INVALID' }
            $mode = [IO.FileMode]::Append
        } else {
            # A full response replaces any partial file.
            $offset = 0
            $size = $response.ContentLength
        }
        if ($size -le 0 -or $size -gt 4GB) { throw 'PACKAGE_SIZE_INVALID' }
        foreach ($root in @([IO.Path]::GetPathRoot($Destination), [IO.Path]::GetPathRoot($env:SystemRoot)) | Select-Object -Unique) {
            if ((New-Object IO.DriveInfo($root)).AvailableFreeSpace -lt (3 * $size + 512MB - $offset)) { throw '0x80073CF4' }
        }
        if ($null -ne $ResumeState) {
            $etag = [string]$response.Headers['ETag']
            $ResumeState['Uri'] = $Release.Uri
            $ResumeState['Validator'] = if ($etag -and -not $etag.StartsWith('W/')) { $etag } else { [string]$response.Headers['Last-Modified'] }
            $ResumeState['Size'] = $size
        }
        $inputStream = $response.GetResponseStream()
        $outputStream = [IO.File]::Open($Destination, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $buffer = New-Object byte[] 1048576
            [long]$total = $offset
            $timer = [Diagnostics.Stopwatch]::StartNew()
            [long]$nextProgressMs = 0
            while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $total += $read
                # A stalled connection fails after ReadWriteTimeout; a slow but working one may need hours.
                if ($total -gt $size -or $total -gt 4GB -or $timer.Elapsed.TotalHours -gt 6) { throw 'DOWNLOAD_LIMIT_EXCEEDED' }
                $outputStream.Write($buffer, 0, $read)
                if ($timer.ElapsedMilliseconds -ge $nextProgressMs -or $total -eq $size) {
                    Write-Progress -Activity (Get-Text 'Downloading official ChatGPT package' 'Загрузка официального пакета ChatGPT') -Status ('{0:N0} / {1:N0} MB' -f ($total / 1MB), ($size / 1MB)) -PercentComplete ([int](100 * $total / $size))
                    $nextProgressMs = $timer.ElapsedMilliseconds + 500
                }
            }
            if ($total -ne $size) { throw 'DOWNLOAD_INCOMPLETE' }
        } finally {
            $outputStream.Dispose(); $inputStream.Dispose()
            Write-Progress -Activity 'Download' -Completed
        }
    } finally { $response.Close() }
}

function Save-ReleasePackage {
    param($Release, [string]$Destination, [hashtable]$ResumeState)
    try {
        Save-OfficialPackage $Release $Destination $ResumeState
        return [pscustomobject]@{ Release = $Release; UsedFallback = $false }
    } catch {
        $network = Get-NetworkException $_
        if (-not $network -or -not $network.Response -or [int]$network.Response.StatusCode -ne 404) { throw }
        $network.Response.Close()
    }
    Write-Step 'The versioned package is not published. Trying OpenAI''s documented download link...' 'Пакет по ссылке с номером версии не опубликован. Проверяю официальную ссылку OpenAI для скачивания...' Yellow
    if ($Release.Architecture -notin @('x64', 'arm64')) { throw 'UNTRUSTED_URL' }
    $fallback = [pscustomobject]@{
        Version = $Release.Version; Architecture = $Release.Architecture
        Uri = 'https://persistent.oaistatic.com/codex-app-prod/ChatGPT-' + $Release.Architecture + '.msix'
    }
    Save-OfficialPackage $fallback $Destination $ResumeState
    return [pscustomobject]@{ Release = $fallback; UsedFallback = $true }
}

function Get-MsixMetadata {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if (-not $entry -or $entry.Length -gt 1MB) { throw 'MANIFEST_INVALID' }
        $stream = $entry.Open()
        $settings = New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create($stream, $settings)
        try { $xml = New-Object Xml.XmlDocument; $xml.XmlResolver = $null; $xml.Load($reader) }
        finally { $reader.Dispose(); $stream.Dispose() }
        $identity = $xml.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Identity"]')
        $target = $xml.SelectSingleNode('//*[local-name()="TargetDeviceFamily" and (@Name="Windows.Desktop" or @Name="Windows.Universal")]')
        if (-not $identity -or -not $target) { throw 'MANIFEST_INVALID' }
        $dependencies = @($xml.SelectNodes('//*[local-name()="PackageDependency"]') | ForEach-Object {
            [pscustomobject]@{ name = $_.GetAttribute('Name'); minVersion = $_.GetAttribute('MinVersion'); publisher = $_.GetAttribute('Publisher') }
        })
        return [pscustomobject]@{
            Name = $identity.GetAttribute('Name'); Publisher = $identity.GetAttribute('Publisher')
            Version = $identity.GetAttribute('Version'); Architecture = $identity.GetAttribute('ProcessorArchitecture')
            MinWindowsVersion = $target.GetAttribute('MinVersion'); Dependencies = $dependencies
        }
    } finally { $archive.Dispose() }
}

function Assert-PackageMetadata {
    param($Metadata, $Release, [string]$WindowsVersion, [switch]$AllowVersionDifference)
    if ($Metadata.Name -cne $script:PackageIdentity -or $Metadata.Publisher -cne $script:PackagePublisher) { throw 'PACKAGE_IDENTITY_MISMATCH' }
    if ($Metadata.Architecture -cne $Release.Architecture) { throw '0x80073D10' }
    if ([string]$Metadata.Version -cnotmatch '^\d{1,5}\.\d{1,5}\.\d{1,5}\.\d{1,5}$') { throw 'PACKAGE_VERSION_MISMATCH' }
    $packageVersion = [version]$Metadata.Version
    foreach ($part in @($packageVersion.Major, $packageVersion.Minor, $packageVersion.Build, $packageVersion.Revision)) { if ($part -gt 65535) { throw 'PACKAGE_VERSION_MISMATCH' } }
    if (-not $AllowVersionDifference -and $packageVersion -ne [version]$Release.Version) { throw 'PACKAGE_VERSION_MISMATCH' }
    if ([version]$Metadata.MinWindowsVersion -gt [version]$WindowsVersion) { throw '0x80073CFD' }
}

function Confirm-OfficialPackage {
    param([string]$Path, $Release, [string]$WindowsVersion, [switch]$AllowVersionDifference)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -cne $script:PackagePublisher) { throw 'PACKAGE_SIGNATURE_INVALID' }
    $metadata = Get-MsixMetadata $Path
    Assert-PackageMetadata $metadata $Release $WindowsVersion -AllowVersionDifference:$AllowVersionDifference
    return [pscustomobject]@{ Metadata = $metadata; Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash; SignatureStatus = 'Valid' }
}

function Get-DependencyFindings {
    param($Metadata)
    foreach ($dependency in $Metadata.Dependencies) {
        $matches = @(Get-AppxPackage -Name $dependency.name -ErrorAction SilentlyContinue | Where-Object {
            [version]$_.Version -ge [version]$dependency.minVersion -and
            [string]$_.Status -eq 'Ok' -and
            ([string]$_.Architecture -eq $Metadata.Architecture -or [string]$_.Architecture -eq 'Neutral') -and
            (-not $dependency.publisher -or $_.Publisher -eq $dependency.publisher)
        })
        if ($matches.Count -eq 0) {
            New-Finding 'DEPENDENCY_MISSING' 'blocker' (Get-Text ('Required dependency: ' + $dependency.name + ' >= ' + $dependency.minVersion) ('Необходима зависимость: ' + $dependency.name + ' >= ' + $dependency.minVersion)) (Get-Text 'Install through the official Microsoft Store installer so Windows can resolve dependencies, or ask IT to deploy the official dependencies.' 'Используйте официальный установщик Microsoft Store для получения зависимостей или попросите ИТ установить официальные зависимости.')
        }
    }
}

function Get-InstallOutcome {
    param([AllowNull()]$Installed, [string]$TargetVersion)
    if ($Installed -and [string]$Installed.Status -eq 'Ok' -and [version]$Installed.Version -ge [version]$TargetVersion) { return 'Installed' }
    # A successful deferred call is not the same as a verified registered update.
    return 'PendingRegistration'
}

function Get-RunningAppProcess {
    # Only this Windows session's ChatGPT processes keep the package in use for this user.
    $session = (Get-Process -Id $PID).SessionId
    $marker = '\WindowsApps\' + $script:PackageIdentity + '_'
    return @([Diagnostics.Process]::GetProcesses() | Where-Object { $_.SessionId -eq $session } | Where-Object {
        try { $_.MainModule.FileName.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0 } catch { $false }
    })
}

function Wait-AppExit {
    # Windows retries a deferred registration without administrator rights when ChatGPT starts again,
    # which fails with 0x80073D28 for this package's service. Install here after ChatGPT has closed.
    $announced = $false
    $shownNames = ''
    while ($true) {
        $running = @(Get-RunningAppProcess)
        if ($running.Count -eq 0) { break }
        if (-not $announced) {
            Write-Step 'ChatGPT is open. Save your work and quit ChatGPT completely, including its icon near the clock. Installation continues automatically after it closes; nothing is closed by force. To postpone, close this window.' 'ChatGPT открыт. Сохраните работу и полностью закройте ChatGPT, включая значок возле часов. Установка продолжится автоматически после закрытия; ничего не закрывается принудительно. Чтобы отложить, закройте это окно.' Yellow
            $announced = $true
        }
        # Name what still runs from the package, e.g. a helper left after the main window closed.
        $names = @($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
        if ($names -ne $shownNames) { Write-Step ('Still running: ' + $names) ('Ещё работают: ' + $names); $shownNames = $names }
        Start-Sleep -Seconds 2
    }
    if ($announced) { Write-Step 'ChatGPT is closed. Do not open it until installation finishes.' 'ChatGPT закрыт. Не открывайте его, пока установка не завершится.' }
}

function New-ProtectedStagingDirectory {
    # AppX's service may not be able to open a package in a user's profile.
    # Create a new directory atomically with explicit, non-inherited permissions.
    $directory = New-Object IO.DirectoryInfo (Join-Path $env:ProgramData ('ChatGPTWindowsInstaller-' + [guid]::NewGuid().ToString('N')))
    if ($directory.Exists) { throw 'STAGING_DIRECTORY_EXISTS' }
    $security = New-Object Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true, $false)
    $administrators = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'
    $system = New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'
    $user = New-Object Security.Principal.SecurityIdentifier (Get-CurrentUserSid)
    $security.SetOwner($administrators)
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($identity in @($administrators, $system)) {
        $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, [Security.AccessControl.FileSystemRights]::FullControl, $inherit, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow))
    }
    $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($user, [Security.AccessControl.FileSystemRights]::ReadAndExecute, $inherit, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow))
    if ($PSVersionTable.PSEdition -eq 'Core') {
        [IO.FileSystemAclExtensions]::Create($directory, $security)
    } else {
        $directory.Create($security)
    }
    return $directory.FullName
}

function Remove-InstallerFile {
    param([string]$Path)
    # Security software may still be scanning a large new file; retry briefly instead of leaving it behind.
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) { return $true }
        try { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop } catch { Start-Sleep -Seconds 1 }
    }
    return -not (Test-Path -LiteralPath $Path)
}

function Remove-EmptyDirectory {
    param([string]$Path)
    # Unlike Remove-Item, this never prompts or deletes contents: a non-empty directory is kept.
    try { [IO.Directory]::Delete($Path, $false) } catch { }
}

function Get-DirectoryOwnerSid {
    param([string]$Path)
    try { return (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { return $null }
}

function Clear-StaleInstallerFiles {
    param([string]$CacheRoot, [string]$StagingRoot)
    # Remove package files left by an interrupted earlier run: this tool's own names only, never
    # recursively, never through links, and only in directories untouched for a day.
    $cutoff = (Get-Date).AddDays(-1)
    $directories = @()
    if ($CacheRoot -and (Test-Path -LiteralPath $CacheRoot)) {
        $directories += @(Get-ChildItem -LiteralPath $CacheRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch '^[a-f0-9]{32}$' })
    }
    if ($StagingRoot -and (Test-Path -LiteralPath $StagingRoot)) {
        # ProgramData is writable by users, so only directories owned by Administrators are ours.
        $directories += @(Get-ChildItem -LiteralPath $StagingRoot -Directory -Filter 'ChatGPTWindowsInstaller-*' -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -cmatch '^ChatGPTWindowsInstaller-[a-f0-9]{32}$' -and (Get-DirectoryOwnerSid $_.FullName) -eq 'S-1-5-32-544'
        })
    }
    foreach ($directory in $directories) {
        if ($directory.LastWriteTime -gt $cutoff -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch '^ChatGPT-(x64|arm64)\.msix$' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }
        Remove-EmptyDirectory $directory.FullName
    }
}

function Install-VerifiedPackage {
    param([string]$Path, $Release, [string]$WindowsVersion)
    # Windows PowerShell draws deployment progress over earlier console lines and can leave them garbled.
    $ProgressPreference = 'SilentlyContinue'
    $null = Confirm-OfficialPackage $Path $Release $WindowsVersion
    $stageDirectory = $null
    $stagePath = $null
    try {
        $stageDirectory = New-ProtectedStagingDirectory
        $stagePath = Join-Path $stageDirectory ('ChatGPT-' + $Release.Architecture + '.msix')
        Copy-Item -LiteralPath $Path -Destination $stagePath -ErrorAction Stop
        # Verify the exact protected copy that Windows will open.
        $null = Confirm-OfficialPackage $stagePath $Release $WindowsVersion
        Add-AppxPackage -Path $stagePath -DeferRegistrationWhenPackagesAreInUse -ErrorAction Stop
        return Get-InstallOutcome (Get-InstalledPackage) $Release.Version
    } finally {
        if ($stageDirectory) {
            $resolved = [IO.Path]::GetFullPath($stageDirectory)
            $parent = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd([char[]]'\/')
            if ((Split-Path $resolved -Parent) -eq $parent -and (Split-Path $resolved -Leaf) -match '^ChatGPTWindowsInstaller-[a-f0-9]{32}$') {
                if ($stagePath) { $null = Remove-InstallerFile $stagePath }
                Remove-EmptyDirectory $resolved
            }
        }
    }
}

function Start-ElevatedInstaller {
    param([string]$EntryPath, [string]$Language, [string]$CallerSid, [switch]$NoPause)
    if ($EntryPath.Contains([char]0)) { throw 'ENTRY_PATH_INVALID' }
    # PowerShell also treats typographic quotes such as U+2019 as single quotes; escape all of them.
    $escapedPath = [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($EntryPath)
    if (@('en', 'ru') -cnotcontains $Language) { throw 'LANGUAGE_INVALID' }
    if ($CallerSid -notmatch '^S-1-5-(\d+-)*\d+$') { throw 'CALLER_SID_INVALID' }
    $invocation = "& '$escapedPath' -Mode Auto -Language '$Language' -CallerSid '$CallerSid'"
    if ($NoPause) { $invocation += ' -NoPause' }
    # A script that cannot start (moved folder, unmapped network drive) must not look like success:
    # without try/catch the command exits 0. -EncodedCommand otherwise collapses nonzero codes to 1.
    $command = 'try { ' + $invocation + ' } catch { exit 3 }; exit $LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $executable = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $process = Start-Process -FilePath $executable -Verb RunAs -WindowStyle Normal -Wait -PassThru -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -ErrorAction Stop
    return $process.ExitCode
}

function Write-Report {
    param($Report, [string]$Directory)
    $null = New-Item -ItemType Directory -Force -Path $Directory
    $file = Join-Path $Directory ('report-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json')
    $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $file -Encoding UTF8
    $textFile = [IO.Path]::ChangeExtension($file, '.txt')
    $lines = @(
        ('ChatGPT Windows Installer ' + $script:ToolVersion)
        ('Result / Результат: ' + $Report.outcome)
        ('UTC: ' + $Report.generatedUtc)
        ''
    )
    if ($Report.system) {
        $lines += 'Windows: ' + $Report.system.windowsVersion
        $lines += 'Architecture / Архитектура: ' + $Report.system.architecture
        if ($Report.system.PSObject.Properties.Name -contains 'installedVersion') { $lines += 'Installed / Установлено: ' + $Report.system.installedVersion }
    }
    $lines += 'Available / Доступно: ' + $Report.latestVersion
    $lines += 'Verified package / Проверенный пакет: ' + $Report.packageVersion
    $lines += 'Registered after run / Зарегистрировано после запуска: ' + $Report.installedVersionAfter
    $lines += ''
    foreach ($finding in $Report.findings) {
        $lines += '[' + $finding.severity + ' / ' + $finding.code + '] ' + $finding.summary
        $lines += $finding.action
        $lines += ''
    }
    $lines += 'Historical errors describe past attempts. They may already be resolved.'
    $lines += 'Исторические ошибки относятся к прошлым попыткам и уже могли быть исправлены.'
    $lines | Set-Content -LiteralPath $textFile -Encoding UTF8
    # Keep the newest 20 runs (JSON and text).
    $old = @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch '^report-\d{8}-\d{6}-[a-f0-9]{6}\.(json|txt)$' } | Sort-Object LastWriteTime -Descending | Select-Object -Skip 40)
    foreach ($file in $old) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
    return $textFile
}

function Invoke-ChatGPTInstaller {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'Diagnose', 'Download')][string]$Mode = 'Auto',
        [ValidateSet('Auto', 'en', 'ru')][string]$Language = 'Auto',
        [switch]$Offline, [string]$CallerSid, [switch]$NoPause, [string]$EntryPath, [ref]$Handoff
    )
    $script:Language = $Language
    if ($Language -eq 'Auto') { $script:Language = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'ru') { 'ru' } else { 'en' } }
    Write-Host ''
    Write-Host ('ChatGPT Windows Installer  ' + $script:ToolVersion) -ForegroundColor White
    Write-Step 'Independent community tool. Official OpenAI packages only.' 'Независимый инструмент сообщества. Только официальные пакеты OpenAI.'
    if ($CallerSid -and $CallerSid -ne (Get-CurrentUserSid)) {
        Write-Step 'A different administrator account was used. Installation stopped to avoid updating the wrong user. Ask IT to deploy for your account.' 'Указана другая учётная запись администратора. Установка остановлена, чтобы не обновить приложение другому пользователю. Попросите ИТ установить его для вашей учётной записи.' Red
        return 2
    }
    if ($Offline -and $Mode -ne 'Diagnose') {
        Write-Step '-Offline is available only with -Mode Diagnose.' '-Offline доступен только вместе с -Mode Diagnose.' Red
        return 2
    }
    $report = [ordered]@{
        toolVersion = $script:ToolVersion; generatedUtc = [DateTime]::UtcNow.ToString('o'); mode = $Mode
        outcome = 'Checking'; system = $null; latestVersion = $null; findings = @(); recentDeploymentErrors = @()
        packageSha256 = $null; signatureStatus = $null; packageVersion = $null
        packageSource = $null; installedVersionAfter = $null; phase = 'Preflight'
    }
    $dataRoot = Join-Path $env:LOCALAPPDATA 'ChatGPTWindowsInstaller'
    $runRoot = $null
    $runDirectory = $null
    $reportNeeded = $true
    $mutex = $null
    $locked = $false
    try {
        # A copy started with "Run as administrator" creates a lock that a standard window cannot open.
        try { $mutex = New-Object Threading.Mutex($false, $script:MutexName) }
        catch { if ($_.Exception -is [UnauthorizedAccessException] -or $_.Exception.InnerException -is [UnauthorizedAccessException]) { throw 'ANOTHER_INSTANCE' }; throw }
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'ANOTHER_INSTANCE' }
        Write-Step 'Checking Windows, installed packages, storage, policies and deployment events...' 'Проверяю Windows, пакеты, место на диске, политики и события установки...'
        $snapshot = Get-SystemSnapshot
        $report.system = $snapshot
        if ($snapshot.PSObject.Properties.Name -contains 'installedVersion') {
            $installedLabel = if ($snapshot.installedVersion) { $snapshot.installedVersion } else { Get-Text 'not installed' 'не установлено' }
            Write-Step ('Installed: ' + $installedLabel + ' | ' + $snapshot.architecture) ('Установлено: ' + $installedLabel + ' | ' + $snapshot.architecture)
        }
        $report.findings = @(Get-PreflightFindings $snapshot)
        $report.recentDeploymentErrors = @(Get-RecentDeploymentErrors)
        foreach ($code in @($report.recentDeploymentErrors | ForEach-Object codes | Select-Object -Unique)) {
            $advice = Get-ErrorAdvice $code
            $advice.severity = 'historical'
            $report.findings += $advice
        }
        $release = $null
        if (-not $Offline -and $snapshot.architecture -in @('x64', 'arm64')) {
            $report.phase = 'ReleaseCheck'
            Write-Step 'Checking the official release feed...' 'Проверяю официальный канал обновлений...'
            $release = Get-LatestRelease $snapshot.architecture
            $report.latestVersion = $release.Version
            Write-Step ('Available: ' + $release.Version) ('Доступно: ' + $release.Version)
        }
        if ($Mode -eq 'Diagnose') {
            $report.outcome = if (@($report.findings | Where-Object severity -eq 'blocker').Count) { 'ActionRequired' } else { 'DiagnosisComplete' }
            Write-Step 'Diagnosis complete. Historical errors are evidence of earlier attempts, not proof of a current fault.' 'Диагностика завершена. Старые ошибки относятся к прошлым попыткам и не доказывают текущий сбой.' Green
            if ($report.outcome -eq 'ActionRequired') { return 2 }
            return 0
        }
        if (@($report.findings | Where-Object severity -eq 'blocker').Count) { $report.outcome = 'ActionRequired'; return 2 }
        if (-not $release) { throw 'RELEASE_UNAVAILABLE' }
        $decision = Get-UpdateDecision (Get-InstalledPackage) $release.Version
        if ($Mode -eq 'Auto' -and $decision -in @('Current', 'NewerInstalled')) {
            $report.outcome = $decision
            Write-Step 'The installed app is current or newer than the public release. No installation is needed.' 'Установленная версия актуальна или новее публичной. Установка не требуется.' Green
            return 0
        }
        if ($Mode -eq 'Auto' -and $decision -eq 'NeedsRepair') {
            $report.findings += New-Finding 'PACKAGE_STATUS_NOT_OK' 'blocker' (Get-Text 'The installed package reports a non-OK status.' 'Установленный пакет сообщает о некорректном состоянии.') (Get-Text 'Inspect Windows deployment events or ask support. This tool does not reset user data to repair an existing package.' 'Проверьте события установки Windows или обратитесь в поддержку. Скрипт не сбрасывает пользовательские данные для восстановления пакета.')
            $report.outcome = 'ActionRequired'; return 2
        }
        if ($Mode -eq 'Auto' -and -not (Test-IsAdministrator)) {
            Write-Step 'Opening the installer as administrator. Approve the Windows prompt if one appears.' 'Открываю установку с правами администратора. Если Windows покажет запрос, подтвердите его.' Yellow
            Write-Step 'Installation continues in the "Administrator" window. This window closes when it finishes.' 'Установка продолжится в окне «Администратор». Это окно закроется, когда она завершится.'
            # Release the per-session lock before starting the elevated copy.
            $mutex.ReleaseMutex(); $locked = $false
            $report.phase = 'Elevation'
            $result = Start-ElevatedInstaller -EntryPath $EntryPath -Language $script:Language -CallerSid (Get-CurrentUserSid) -NoPause:$NoPause
            if ($result -in @(0, 1, 2, 10)) {
                # The administrator window has already shown its result and report.
                $reportNeeded = $false
                if ($null -ne $Handoff) { $Handoff.Value = $true }
                return $result
            }
            $report.outcome = 'Failed'
            if ($result -eq 3) {
                $report.findings += New-Finding 'ELEVATED_START_FAILED' 'error' (Get-Text 'The administrator window could not start this tool.' 'Окно администратора не смогло запустить скрипт.') (Get-Text 'Extract the entire ZIP to a local folder such as Downloads (not a network drive), then run Start.cmd again.' 'Распакуйте весь ZIP в локальную папку, например «Загрузки» (не на сетевой диск), и снова запустите Start.cmd.')
                return 3
            }
            $report.findings += New-Finding 'ELEVATED_WINDOW_CLOSED' 'error' (Get-Text ('The administrator window closed before reporting a result (code ' + $result + ').') ('Окно администратора закрылось, не сообщив результат (код ' + $result + ').')) (Get-Text 'If it had already finished or you closed it to postpone the update, nothing else is needed. Otherwise run Start.cmd again; it checks the installed version first.' 'Если установка уже завершилась или вы закрыли окно, чтобы отложить обновление, больше ничего делать не нужно. Иначе снова запустите Start.cmd: сначала он проверит установленную версию.')
            return 1
        }
        # Download mode keeps its verified package, so it never shares the folder cleaned below.
        $runRoot = Join-Path $dataRoot $(if ($Mode -eq 'Download') { 'downloads' } else { 'cache' })
        $stagingRoot = $null
        if (Test-IsAdministrator) { $stagingRoot = $env:ProgramData }
        Clear-StaleInstallerFiles (Join-Path $dataRoot 'cache') $stagingRoot
        $runDirectory = Join-Path $runRoot ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Force -Path $runDirectory
        $packagePath = Join-Path $runDirectory ('ChatGPT-' + $release.Architecture + '.msix')
        $report.phase = 'Download'
        Write-Step ('Downloading version ' + $release.Version + ' from OpenAI...') ('Загружаю версию ' + $release.Version + ' с сервера OpenAI...')
        # Retry transient transport failures and resume the partial file; never retry signature or policy failures.
        $resume = @{}
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try { $download = Save-ReleasePackage $release $packagePath $resume; break }
            catch {
                if ($attempt -eq 5 -or -not (Test-TransientNetworkFailure $_)) { throw }
                Write-Step 'The download was interrupted; resuming...' 'Загрузка прервалась; продолжаю...' Yellow
                Start-Sleep -Seconds ([int][Math]::Pow(2, $attempt - 1))
            }
        }
        Write-Step 'Verifying the Windows signature, package identity, version and compatibility...' 'Проверяю подпись Windows, издателя, версию и совместимость пакета...'
        $report.phase = 'Verification'
        $verified = Confirm-OfficialPackage $packagePath $download.Release $snapshot.windowsVersion -AllowVersionDifference:$download.UsedFallback
        $report.packageVersion = $verified.Metadata.Version
        $report.packageSource = if ($download.UsedFallback) { 'DocumentedLatest' } else { 'Versioned' }
        if ($report.packageVersion -ne $report.latestVersion) {
            $report.findings += New-Finding 'RELEASE_CHANNEL_DIFFERENCE' 'warning' (Get-Text ('The feed advertises ' + $report.latestVersion + '; the signed download contains ' + $report.packageVersion + '.') ('Канал обновлений сообщает ' + $report.latestVersion + ', а подписанный пакет содержит ' + $report.packageVersion + '.')) (Get-Text 'Only the verified package version can be installed. A newer installed version will be kept. Run this tool again later to check for the advertised release.' 'Установить можно только проверенную версию пакета. Более новая установленная версия будет сохранена. Проверьте наличие объявленного релиза позже.')
        }
        # Bind installation and the final comparison to the actual signed package.
        $release = [pscustomobject]@{Version=$report.packageVersion;Architecture=$download.Release.Architecture;Uri=$download.Release.Uri}
        $report.packageSha256 = $verified.Sha256
        $report.signatureStatus = $verified.SignatureStatus
        $report.findings += @(Get-DependencyFindings $verified.Metadata)
        if ($Mode -eq 'Download') {
            $report.outcome = 'DownloadedAndVerified'
            Write-Step ('Verified package: ' + $packagePath) ('Проверенный пакет: ' + $packagePath) Green
            return 0
        }
        if (@($report.findings | Where-Object severity -eq 'blocker').Count) { $report.outcome = 'ActionRequired'; return 2 }
        # Recheck after the download: another installer may have updated the app meanwhile.
        $decision = Get-UpdateDecision (Get-InstalledPackage) $release.Version
        if ($decision -in @('Current', 'NewerInstalled')) {
            $report.outcome = $decision
            Write-Step 'The verified package is not newer than the installed app. Nothing was installed.' 'Проверенный пакет не новее установленного приложения. Ничего не установлено.' Green
            return 0
        }
        if ($decision -eq 'NeedsRepair') { throw 'PACKAGE_STATUS_CHANGED' }
        # Deferred registration cannot finish this package later (see Wait-AppExit), so interactive runs
        # wait for ChatGPT to close and install again if it was reopened before Windows finished.
        for ($attempt = 1; ; $attempt++) {
            if (-not $NoPause) { $report.phase = 'WaitingForAppExit'; Wait-AppExit }
            Write-Step 'Installing the verified package. Running applications will not be force-closed.' 'Устанавливаю проверенный пакет. Запущенные приложения не закрываются принудительно.'
            $report.phase = 'Deployment'
            $report.outcome = Install-VerifiedPackage $packagePath $release $snapshot.windowsVersion
            $report.phase = 'RegistrationCheck'
            if ($report.outcome -ne 'PendingRegistration' -or $NoPause -or $attempt -ge 3) { break }
            Write-Step 'ChatGPT was opened again before Windows finished the update.' 'ChatGPT снова открыли до завершения обновления.' Yellow
        }
        if ($report.outcome -eq 'PendingRegistration') {
            Write-Step 'Windows prepared the update, but ChatGPT was still open. Close ChatGPT completely and run Start.cmd again. Reopening ChatGPT alone cannot finish this update: its Windows service needs administrator rights.' 'Windows подготовила обновление, но ChatGPT ещё был открыт. Полностью закройте ChatGPT и снова запустите Start.cmd. Простой перезапуск ChatGPT не завершит обновление: для его службы Windows нужны права администратора.' Yellow
            return 10
        }
        Write-Step 'The new installed version has been verified. Open ChatGPT normally.' 'Новая установленная версия проверена. Откройте ChatGPT обычным способом.' Green
        return 0
    }
    catch {
        $report.outcome = 'Failed'
        $code = Get-ExceptionCode $_
        $network = Get-NetworkException $_
        $safeCustom = @('FEED_FORMAT_CHANGED', 'FEED_IDENTITY_MISMATCH', 'FEED_VERSION_INVALID', 'FEED_TOO_LARGE', 'UNTRUSTED_URL', 'UNEXPECTED_HTTP_STATUS', 'RELEASE_UNAVAILABLE', 'PACKAGE_SIGNATURE_INVALID', 'PACKAGE_IDENTITY_MISMATCH', 'PACKAGE_VERSION_MISMATCH', 'PACKAGE_SIZE_INVALID', 'MANIFEST_INVALID', 'DOWNLOAD_INCOMPLETE', 'DOWNLOAD_LIMIT_EXCEEDED', 'DOWNLOAD_RANGE_INVALID', 'PACKAGE_STATUS_CHANGED')
        if ($_.Exception.Message -eq 'ANOTHER_INSTANCE') {
            $code = 'ANOTHER_INSTANCE'
            $report.findings += New-Finding $code 'error' (Get-Text 'Another copy of this tool is already running.' 'Скрипт уже запущен в другом окне.') (Get-Text 'Let the other window finish, including an Administrator window that may be waiting for ChatGPT to close, then run the tool again.' 'Дождитесь завершения другого окна, в том числе окна «Администратор», которое может ждать закрытия ChatGPT, затем запустите скрипт снова.')
        } elseif ($_.Exception.Message -in $safeCustom) {
            $code = $_.Exception.Message
            $report.findings += New-Finding $code 'error' (Get-Text 'A required integrity or workflow check did not pass.' 'Не пройдена обязательная проверка целостности или выполнения.') (Get-Text 'Use the latest release of this tool and check the official installer. Signature checks and source checks are never bypassed.' 'Используйте свежую версию скрипта и проверьте официальный установщик. Проверки подписи и источника не обходятся.')
        } elseif ($network) {
            $networkCode = switch ($network.Status) {
                'NameResolutionFailure' { '0x80072EE7' }
                'Timeout' { '0x80072EE2' }
                'TrustFailure' { '0x80072F8F' }
                'SecureChannelFailure' { '0x80072F8F' }
                default { '0x80072EFD' }
            }
            if ($network.Response) {
                $status = [int]$network.Response.StatusCode
                $code = 'HTTP_' + $status
                $report.findings += New-Finding $code 'error' (Get-Text ('The official server returned HTTP ' + $status + '.') ('Официальный сервер ответил HTTP ' + $status + '.')) (Get-Text 'This response alone cannot identify a country restriction. Check network/proxy policy and try again later; 404 means this package URL is unavailable.' 'Этот ответ сам по себе не доказывает региональное ограничение. Проверьте сеть и прокси, повторите позже; 404 означает, что пакет по этой ссылке недоступен.')
            } else {
                $code = $networkCode
                $report.findings += Get-ErrorAdvice $code
            }
        } elseif (Test-TransientNetworkFailure $_) {
            # The connection dropped during the download, even after resuming.
            $code = '0x80072EFD'
            $report.findings += Get-ErrorAdvice $code
        } else { $report.findings += Get-ErrorAdvice $code }
        Write-Step ('Stopped: ' + $code + '. See the diagnostic report below.') ('Остановлено: ' + $code + '. Подробности в отчёте ниже.') Red
        return 1
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        if ($mutex) { $mutex.Dispose() }
        if ($reportNeeded) {
            try { $finalPackage = Get-InstalledPackage; if ($finalPackage) { $report.installedVersionAfter = [string]$finalPackage.Version } } catch { }
            foreach ($finding in $report.findings | Where-Object severity -in @('blocker', 'error', 'warning')) {
                Write-Host ('[' + $finding.code + '] ' + $finding.summary) -ForegroundColor Yellow
                Write-Host $finding.action
            }
            try {
                $reportPath = Write-Report $report (Join-Path $dataRoot 'reports')
                Write-Step ('Local diagnostic report: ' + $reportPath) ('Локальный отчёт диагностики: ' + $reportPath)
            } catch { Write-Step 'The report could not be saved.' 'Не удалось сохранить отчёт.' Yellow }
        }
        # No recursive deletion. Only this run's single downloaded file is removed.
        if ($runDirectory -and ($Mode -ne 'Download' -or $report.outcome -ne 'DownloadedAndVerified')) {
            $allowedRoot = [IO.Path]::GetFullPath($runRoot) + [IO.Path]::DirectorySeparatorChar
            $resolved = [IO.Path]::GetFullPath($runDirectory)
            if ($resolved.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
                $null = Remove-InstallerFile $packagePath
                Remove-EmptyDirectory $resolved
            }
        }
    }
}

Export-ModuleMember -Function Invoke-ChatGPTInstaller, ConvertTo-Release, Assert-OfficialUri, Get-ErrorCodes, Get-ErrorAdvice, Get-ExceptionCode, Get-UpdateDecision, Get-PreflightFindings, Get-MsixMetadata, Assert-PackageMetadata, Confirm-OfficialPackage, Get-InstallOutcome
