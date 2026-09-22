#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $root 'tests\Run-Tests.ps1')
$output = [IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Path $output -Force
$zipPath = Join-Path $output 'ChatGPT-Windows-Installer.zip'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# A new archive is created only in the explicit output directory.
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    $include = @('Start.cmd','Diagnose.cmd','Install-ChatGPT.ps1','README.md','README.ru.md','LICENSE','SECURITY.md','CONTRIBUTING.md','src','docs','tests','tools')
    foreach ($item in $include) {
        $path = Join-Path $root $item
        foreach ($file in Get-ChildItem -LiteralPath $path -Recurse -File) {
            $relative = $file.FullName.Substring($root.Length).TrimStart([char[]]'\/').Replace('\','/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, ('ChatGPT-Windows-Installer/' + $relative), [IO.Compression.CompressionLevel]::Optimal)
        }
    }
} finally { $archive.Dispose() }
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
($hash + '  ChatGPT-Windows-Installer.zip') | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
Write-Host ('Built: ' + $zipPath)
