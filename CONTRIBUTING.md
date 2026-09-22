# Contributing

Keep installation decisions explicit, the default action repeatable and user data intact. New error entries need a primary Microsoft/OpenAI reference and a realistic action; do not turn every error into an automatic registry or service edit.

## Run tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
pwsh.exe -NoProfile -File .\tests\Run-Tests.ps1
```

No package manager or Pester installation is required. Windows PowerShell 5.1 is the production runtime. Preserve UTF-8 BOMs in `.ps1` / `.psm1` files so Russian text works there; JSON is read explicitly as UTF-8.

## Validation scope

Automated tests cover source/feed injection rejection, version/downgrade decisions, incompatible manifests, unsigned package rejection, offline diagnosis, same-user elevation, required dependencies, in-use/deferred registration, failed downloads, policy refusals and report privacy. Deployment calls are mocked: the tests do not install/uninstall applications or change Windows settings.

Initial real-machine validation checked read-only diagnostics on Windows x64, the current release feed, native package selection and the signature, identity and manifest of the official x64 package. Full installation on a clean machine, ARM64 deployment, UAC interaction under all account types, proxy-authenticated networks and enterprise restrictions require separate hands-on validation. Do not describe mocked tests as successful real installation.

Before an installation-related release, use disposable Windows test machines with snapshots. Verify fresh install, existing app update, app-in-use behavior, standard-account handling and missing dependencies; check user data and final registered version. Report exactly which cases were exercised.

## Public repository hygiene

Commit only code, docs and synthetic test data. Never commit downloaded MSIX packages, local reports, Windows event exports, private file paths or credentials. Keep write access restricted and use GitHub's security-reporting features for sensitive issues.

## Release

Run `tools\Build-Release.ps1` in Windows PowerShell. It runs tests and creates a ZIP plus `SHA256SUMS.txt` in the requested output directory. Create a tag matching `ToolVersion`, publish those assets, and describe validation limitations in the release notes. The archive contains no ChatGPT binaries.
