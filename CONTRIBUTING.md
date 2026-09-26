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

Version 1.0.3 added workflow tests for waiting until ChatGPT closes, unfinished handoffs (exit code 3 and a closed Administrator window), dropped connections surfacing as `IOException`, and the real handoff with a typographic apostrophe (U+2019) in the path or an unstartable script. The real download code runs against a scripted server that drops the connection, resumes with `If-Range`, and restarts when the validator is stale. Leftover cleanup, report rotation and a lock held by an elevated window (Windows PowerShell only) are covered too. The protected ProgramData cleanup test runs only in an elevated test process, as on CI.

Version 1.0.4 replaces the three-attempt loop with one verified deployment and adds explicit target-app shutdown consent. Tests cover menu consent, postponement, manual waiting, noninteractive defaults, the CLI switch through a real encoded handoff, unchanged registration after shutdown, policy/signature refusal, and the non-mutating Diagnose/current-version paths. Native process discovery runs read-only against real processes; synthetic identities cover package family, helper paths, unrelated publishers and missing information. Real target shutdown and successful end-to-end deployment are not claimed by these mocked tests.

On 2026-09-26, 446 assertions passed in Windows PowerShell 5.1 and 444 in PowerShell 7. In a separate read-only 32-bit Windows PowerShell reproduction, the old `MainModule` detector found zero ChatGPT processes while the native package detector found all 11. The new detector also found 11 in the 64-bit host. This establishes a cross-bitness failure in the old detector, but the earlier installer report did not record host bitness, so it cannot establish that as the cause of that particular run. The extracted release passed offline diagnosis; no real application was closed or updated during these checks.

A separate live same-user UAC fixture on the validation machine verified administrator elevation, forwarded arguments and return code 10 through the production handoff function. It performed no package installation.

Initial real-machine validation checked read-only diagnostics on Windows x64, the current release feed, native package selection and the signature, identity and manifest of the official x64 package. Full installation on a clean machine, ARM64 deployment, UAC interaction under all account types, proxy-authenticated networks and enterprise restrictions require separate hands-on validation. Do not describe mocked tests as successful real installation.

On 2026-09-22, a real Windows 11 x64 run of version 1.0.1 exercised same-user UAC, HTTP 404 fallback, the complete official download, signature and manifest checks, protected ProgramData staging and `Add-AppxPackage`. Windows accepted package `26.915.4065.0` for deferred registration while `26.903.8094.0` was running. The report correctly returned `PendingRegistration` with no error findings; it did not claim the advertised `26.917.6896.0` was installed. Activation after closing the app was still pending at release time.

On 2026-09-23, the same machine ran version 1.0.2 while ChatGPT was open. Windows deferred `26.917.6896.0`, then failed the deferred registration seven times with `0x80073D28` when the app restarted: that registration runs without administrator rights. A second elevated run with ChatGPT closed installed it (`Installed`). The `26.915.4065.0` package staged by the 1.0.1 run was never registered. Version 1.0.3 was checked with the mocked suite on Windows PowerShell 5.1 and a read-only smoke run: Diagnose and an already-current Auto run against the live feed, which also detected the running app. Its wait-then-install path and resuming after a real dropped connection still need a real update to validate.

Before an installation-related release, use disposable Windows test machines with snapshots. Verify fresh install, existing app update, app-in-use behavior, standard-account handling and missing dependencies; check user data and final registered version. Report exactly which cases were exercised.

## Public repository hygiene

Commit only code, docs and synthetic test data. Never commit downloaded MSIX packages, local reports, Windows event exports, private file paths or credentials. Keep write access restricted and use GitHub's security-reporting features for sensitive issues.

## Release

Run `tools\Build-Release.ps1` in Windows PowerShell. It runs tests and creates a ZIP plus `SHA256SUMS.txt` in the requested output directory. Create a tag matching `ToolVersion`, publish those assets, and describe validation limitations in the release notes. The archive contains no ChatGPT binaries.
