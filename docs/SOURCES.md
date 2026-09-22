# Official sources and release contract

Reviewed: 2026-09-22. These endpoints and signing details can change independently of this project.

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

The release feed is used to compare versions before downloading hundreds of megabytes. The version-specific URL keeps the downloaded package tied to that decision. The signed package version must match the feed, and newer installed versions are never downgraded.

The main installation command is current-user `Add-AppxPackage` with deferred registration. It intentionally does not perform all-user provisioning or install an offline license; follow the official deployment guide when that scope is required.
