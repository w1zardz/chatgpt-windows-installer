# Official sources and release contract

Reviewed: 2026-09-23. These endpoints and signing details can change independently of this project.

| Purpose | Source |
| --- | --- |
| Product identity, architecture downloads, admin requirements | [OpenAI Windows deployment](https://learn.chatgpt.com/docs/enterprise/windows-deployment) |
| Latest x64 package (documented) | `https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix` |
| Latest ARM64 package (documented) | `https://persistent.oaistatic.com/codex-app-prod/ChatGPT-arm64.msix` |
| Release metadata used by the installed official app | `https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json` |
| Version-specific package used by this tool | `https://persistent.oaistatic.com/codex-app-prod/releases/{buildVersion}/ChatGPT-{x64\|arm64}.msix` |
| Windows installation error meanings | [Microsoft AppX troubleshooting](https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting) |
| Deferred registration | [Microsoft Add-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/add-appxpackage) |
| Store region changes | [Microsoft Support](https://support.microsoft.com/en-us/accounts-billing/change-your-country-or-region-in-microsoft-store) |
| OpenAI country availability | [OpenAI Help](https://help.openai.com/en/articles/7947663) |

The feed and version-specific URL convention were observed in the official Windows app and confirmed against its actual update request. They are distribution implementation details, **not a promised public API**. The script requires schema 1, product `9PLM9XGG6VKS`, package `OpenAI.Codex`, a four-part numeric version, and the expected HTTPS host/path. Unexpected changes stop the tool.

Package identity and certificate subject checked by this release:

```text
Name:      OpenAI.Codex
Publisher: CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B
```

Trust also requires `Get-AuthenticodeSignature` to return `Valid`, which delegates signature/chain verification to Windows. A matching text string without a valid signature is insufficient. The manifest is read as XML with external entities and DTDs disabled, without extracting or executing package files.

No downloaded code is evaluated as PowerShell. Feed values are not interpolated into commands. Package downloads reject redirects, arbitrary hosts, credentials in URLs, query strings and unexpected paths. No TLS or package-signature bypass is implemented.

The release feed is used to compare versions before downloading hundreds of megabytes. A version-specific download must match the advertised version exactly. If that URL returns HTTP 404, the tool tries the documented architecture-specific latest URL, still restricted to the same OpenAI HTTPS host. Authentication, TLS and signature failures never trigger a source fallback.

The documented download may lag behind or be ahead of the feed. After Windows validates the signature, the tool validates the manifest identity, publisher, architecture, numeric version and OS compatibility, then binds deployment to that actual package version. Both advertised and verified versions are reported with a warning if they differ. The installation boundary verifies the signature again and requires this exact package version. Newer installed versions are never downgraded.

On 2026-09-22, the feed advertised `26.917.6896.0` while its version-specific x64 URL returned HTTP 404. Version 1.0.0 stopped with a generic .NET wrapper error. Version 1.0.1 adds the documented fallback and recognizes nested network exceptions so reports retain HTTP status and transient failures can be retried.

An interrupted download resumes with an HTTP range request that carries `If-Range` with the first response's strong `ETag` (or `Last-Modified`). The partial file is reused only for the same URL within the same run, and the reply must be `206` with exactly the expected `Content-Range`; a `200` reply replaces the partial file. On 2026-09-23 the production host answered range requests with `206`, honored `If-Range` with both validators, and returned the full file (`200`) for a stale `ETag`.

The main installation command is current-user `Add-AppxPackage` with deferred registration. It intentionally does not perform all-user provisioning or install an offline license; follow the official deployment guide when that scope is required.

Deferred registration alone cannot complete an update of this package. On 2026-09-23 (version 1.0.2, Windows 11 x64), `26.917.6896.0` was deferred while ChatGPT ran. When the app was restarted, Windows attempted `RegisterByPackageFamilyName` without administrator rights and failed seven times with `0x80073D28` ("Administrator privileges required to install packaged service"). A second elevated `Add-AppxPackage` with the app closed registered the already staged package in under a second. Since version 1.0.3, interactive runs therefore wait in the Administrator window until ChatGPT is closed and install then; `-NoPause` runs and repeated reopening still end with exit code `10`.

The package handed to AppX is a verified copy in a newly created protected `%ProgramData%` directory. On the validation machine, deployment from the user-profile cache failed with `0x80073CF0` / `0x80070003`, while the identical signed package in ProgramData was accepted for deferred registration. This is an observed path-dependent failure, not proof of a particular underlying Windows defect. The tool does not modify permissions on existing directories.
