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

Version 1.0.1 adds regression coverage for wrapped .NET HTTP exceptions, the documented fallback on 404, no fallback on 403, bounded timeout retries, fallback signature rejection, feed/package version differences, no downgrade to an older fallback package, and handing Windows the staged copy. Run both PowerShell engines after modifying these paths.

Version 1.0.2 executes the real encoded handoff command in a child Windows PowerShell process and verifies exit codes 0, 1, 2 and 10, including an entry path containing spaces and an apostrophe. Only the UAC request is replaced for this test; the encoded command and child process are real. This prevents PowerShell from collapsing action-required/pending-registration results to generic exit code 1.

A separate live same-user UAC fixture on the validation machine verified administrator elevation, forwarded arguments and return code 10 through the production handoff function. It performed no package installation.

Initial real-machine validation checked read-only diagnostics on Windows x64, the current release feed, native package selection and the signature, identity and manifest of the official x64 package. Full installation on a clean machine, ARM64 deployment, UAC interaction under all account types, proxy-authenticated networks and enterprise restrictions require separate hands-on validation. Do not describe mocked tests as successful real installation.

On 2026-09-22, a real Windows 11 x64 run of version 1.0.1 exercised same-user UAC, HTTP 404 fallback, the complete official download, signature and manifest checks, protected ProgramData staging and `Add-AppxPackage`. Windows accepted package `26.915.4065.0` for deferred registration while `26.903.8094.0` was running. The report correctly returned `PendingRegistration` with no error findings; it did not claim the advertised `26.917.6896.0` was installed. Activation after closing the app was still pending at release time.

Before an installation-related release, use disposable Windows test machines with snapshots. Verify fresh install, existing app update, app-in-use behavior, standard-account handling and missing dependencies; check user data and final registered version. Report exactly which cases were exercised.

## Public repository hygiene

Commit only code, docs and synthetic test data. Never commit downloaded MSIX packages, local reports, Windows event exports, private file paths or credentials. Keep write access restricted and use GitHub's security-reporting features for sensitive issues.

## Release

Run `tools\Build-Release.ps1` in Windows PowerShell. It runs tests and creates a ZIP plus `SHA256SUMS.txt` in the requested output directory. Create a tag matching `ToolVersion`, publish those assets, and describe validation limitations in the release notes. The archive contains no ChatGPT binaries.
