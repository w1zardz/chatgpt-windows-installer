# Security and privacy

This is a community installer wrapper, not an OpenAI or Microsoft product. Inspect the source before approving administrator access.

## Boundaries

- Production OpenAI host and expected paths only; no third-party package mirrors.
- Windows signature/chain validation plus a pinned publisher subject and manifest identity.
- Fresh verification immediately before the package-installation call.
- No `Invoke-Expression`, downloaded script execution, signature bypass, downgrade flag, process killing, app-data reset, registry repair or blanket AppX re-registration.
- No antivirus, SmartScreen, firewall, execution-policy persistence, country, proxy or corporate-policy changes.
- Administrator consent through Windows UAC; no stored passwords or elevation bypass.
- Current-user deployment only. A UAC handoff to a different account is rejected.
- No scheduled tasks, telemetry, background agent or self-update.

The `.cmd` launcher uses process-scoped `-ExecutionPolicy Bypass` so a locally downloaded script can run. This is not a digital signature and does not override Group Policy. Organizations requiring signed scripts should review and sign the source through their own process.

## Local reports

The tool writes text and JSON reports only to its own directory under Local AppData. It records technical state: OS/app versions, architecture, selected service/policy states, Windows home region and relevant error codes/timestamps. It does not copy raw event messages, user/device names, SIDs, chats, account tokens, credentials or proxy URLs. Raw exceptions are not printed into reports.

Ordinary download requests still disclose normal connection metadata to OpenAI's server and to your configured network/proxy. `-Mode Diagnose -Offline` skips network access.

Inspect reports before sharing. Do not upload credentials, raw Windows event exports, private app data or corporate configuration to a public issue. Reports, packages and local test artifacts are excluded from version control.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** feature for a confidential report if enabled. If unavailable, open a public issue containing only a request for a private reporting channel; do not post exploit details, secrets or personal data. Never submit a real token as a reproduction example.

Windows, network, AppX and upstream installer changes can introduce incompatibilities. Unknown conditions fail with advice rather than attempting unrestricted repairs.
