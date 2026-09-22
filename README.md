# ChatGPT Windows Installer & Update Fix

[![Windows tests](https://github.com/w1zardz/chatgpt-windows-installer/actions/workflows/test.yml/badge.svg)](https://github.com/w1zardz/chatgpt-windows-installer/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)](https://learn.microsoft.com/powershell/)

**Install, update and diagnose the official ChatGPT desktop app on Windows.** A readable PowerShell script with a double-click launcher, official downloads, signature verification and explanations for common Microsoft Store / MSIX errors, including **0x80073D28**.

**[Download the latest ZIP](https://github.com/w1zardz/chatgpt-windows-installer/releases/latest/download/ChatGPT-Windows-Installer.zip)** · **[Русская инструкция](README.ru.md)** · [Troubleshooting](docs/TROUBLESHOOTING.md)

Independent community project. Not made by, sponsored by, or affiliated with OpenAI or Microsoft. No “fix every error” guarantee.

## Install or update ChatGPT in one launch

1. Download the ZIP above and **extract the entire folder**.
2. Double-click **`Start.cmd`**.
3. Approve the Windows administrator prompt if installation is needed.

The script detects x64 / ARM64, checks the latest public release, downloads the official package and verifies its Windows signature, signing identity, package identity, version and Windows requirements before installation. Run the same launcher whenever you want to check for another update. An already current or newer installation is left alone.

If ChatGPT is running, Windows can defer registration. **Save work, fully close ChatGPT, reopen it, then run the launcher again to confirm the installed version.** “Pending registration” is reported separately from verified installation.

The Windows consent prompt and managed-device permissions cannot be made into zero-click steps. Read the scripts before running them with administrator privileges.

## What it handles automatically

- Chooses the package for native **x64 or ARM64**, including architecture checks before deployment.
- Resolves the latest version on each run, instead of keeping an obsolete download URL in a script.
- Installs or updates directly from OpenAI's distribution server, without requiring you to browse Microsoft Store.
- Requests administrator permission for installation of packaged services, the cause of **`0x80073D28`**.
- Retries a transient interrupted connection once and downloads into a new run folder.
- Verifies the downloaded package and refuses unexpected publishers, versions or architectures.
- Preserves newer installations and defers registration when the app is in use.
- Produces local text and JSON diagnostics with an error catalog, suggested next steps and recent relevant deployment codes.

It detects or explains additional failures involving dependencies, disk space, unsupported Windows versions, disabled services, policies, certificates, DNS/TLS, package conflicts and pending restarts. Some need an administrator, Windows repair, a supported region, or an upstream fix. See the [coverage and limitations](docs/TROUBLESHOOTING.md).

## Which ChatGPT app?

This project targets the **current ChatGPT desktop app**, whose Windows package is **`OpenAI.Codex`** and Store product ID is **`9PLM9XGG6VKS`**. The old package name can still appear in errors after the product name changes. OpenAI identifies this package in its [Windows deployment documentation](https://learn.chatgpt.com/docs/enterprise/windows-deployment).

The separate older `OpenAI.ChatGPT-Desktop` app is detected where installed. This tool does not uninstall it, migrate its data, or update that legacy package in place.

## Diagnose without installing

Double-click **`Diagnose.cmd`**. It reads local state and checks the official release feed, but does not install packages or request elevation.

Advanced commands, from **Windows PowerShell** in the extracted folder:

```powershell
# Local-only diagnosis: no network requests
.\Install-ChatGPT.ps1 -Mode Diagnose -Offline

# English or Russian output
.\Install-ChatGPT.ps1 -Mode Diagnose -Language en
.\Install-ChatGPT.ps1 -Mode Diagnose -Language ru

# Download and verify the package without installing it
.\Install-ChatGPT.ps1 -Mode Download
```

If local script policy blocks these commands, use `Start.cmd` / `Diagnose.cmd`. The launcher sets execution policy only for its own PowerShell process. It does not change the machine's policy or override an organization's Group Policy.

## Russia, relocation and Microsoft Store region

If you previously used Windows or a Microsoft account in **Russia / the Russian Federation**, and then moved, it is reasonable to check whether your **Windows country and Microsoft account country still match your actual situation**. Microsoft documents that application availability can differ by region and recommends region changes when moving long-term. See [Microsoft's region guidance](https://support.microsoft.com/en-us/accounts-billing/change-your-country-or-region-in-microsoft-store).

Having “some connection to Russia,” speaking Russian, or using a Russian keyboard does **not** establish the cause of an installation failure. This tool does not infer citizenship, inspect account history, locate you by IP, change your region, or claim to diagnose a server-side regional decision.

At the documentation review date (2026-09-22), Russia is absent from OpenAI's [supported-country list](https://help.openai.com/en/articles/7947663). Check that live list for current availability. **Installing an app does not establish access to the ChatGPT service.** This project fixes eligible local installation/update problems; it does not change account eligibility or regional restrictions.

## Updates after a PowerShell installation

A manual installation does **not** inherently turn off the app's built-in updater. This launcher is an additional way to check for and install updates when the normal route fails. It creates no scheduled task, background service or automatic self-update mechanism. The app's own behavior is described in [OpenAI's update guidance](https://learn.chatgpt.com/docs/enterprise/windows-deployment#manage-app-updates).

## Requirements and reports

- Windows 10 build 19041+ or Windows 11, x64 / ARM64. The actual MSIX minimum version is also checked.
- Windows PowerShell 5.1 and the Windows AppX deployment components. `Start.cmd` selects Windows PowerShell automatically.
- Internet access to `persistent.oaistatic.com` for normal operation; enough disk space for download and extraction.
- Administrator approval when installing. Elevation under a **different account** stops rather than installing for the wrong user.

Reports are stored in `%LOCALAPPDATA%\ChatGPTWindowsInstaller\reports`. Verified downloads from `-Mode Download` remain in the tool's own `cache` folder. Automatic mode deletes only its own downloaded file after use.

No report is uploaded. Reports include Windows/app versions, Windows home region, selected service/policy states and relevant error codes. They exclude raw event messages, usernames, computer names, SIDs, account credentials, proxy URLs and chats. Review any report before sharing it. See [security and privacy](SECURITY.md).

Exit codes: **0** completed/current; **1** failed; **2** user/administrator action required; **10** Windows accepted the update, registration still needs verification after closing the app.

## Trust, sources and maintenance

The code uses the production release feed embedded in the official app, then constructs a version-specific URL on the same OpenAI host. These distribution details can change. A changed feed schema, identity or signing publisher stops the tool; it never falls back to a third-party package mirror.

- [Official Windows deployment and MSIX downloads](https://learn.chatgpt.com/docs/enterprise/windows-deployment)
- [Microsoft's AppX deployment errors](https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting)
- [Microsoft's deferred app update behavior](https://learn.microsoft.com/en-us/powershell/module/appx/add-appxpackage#example-2-update-an-app-but-defer-registration-until-the-app-has-closed)
- [Release source contract](docs/SOURCES.md)

Package binaries are not hosted in this repository. The GitHub release ZIP contains this project's source scripts and documentation; `SHA256SUMS.txt` in each release identifies that ZIP. A checksum verifies download integrity, not publisher identity; these community scripts are not Authenticode-signed.

## Development and verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Tests cover source validation, malformed manifests/feed data, package identity, architecture, version decisions, signature rejection, permission handoff, deferred updates, policy failures, privacy and installation side-effect boundaries. They mock Windows package installation; they do not install ChatGPT on your computer. CI runs on Windows with both Windows PowerShell and PowerShell 7.

See [CONTRIBUTING.md](CONTRIBUTING.md). MIT licensed. ChatGPT, Codex, OpenAI, Windows and Microsoft Store are names belonging to their respective owners.
