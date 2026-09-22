# ChatGPT won't install or update on Windows

[Download](https://github.com/w1zardz/chatgpt-windows-installer/releases/latest) · [English guide](../README.md) · [По-русски](../README.ru.md)

Run `Diagnose.cmd` first if you want a report without installation. The full bilingual error catalog is [src/errors.json](../src/errors.json); these groups explain the available actions.

| Symptom / representative code | Tool behavior | What may still need your action |
| --- | --- | --- |
| `0x80073D28`, packaged service requires admin | Requests UAC before installation | Approve as the same Windows user, or ask IT for deployment |
| `0x80073D02`, app is in use | Uses deferred registration | Fully close and reopen ChatGPT, then verify again |
| `0x80073D06`, newer version installed | Keeps the newer version | None; no downgrade is attempted |
| AppX cannot open a verified file in the user-profile cache | Installs a reverified copy from a new protected ProgramData directory | If Windows still refuses it, preserve the report; no existing permissions are reset |
| Store app unavailable or Store delivery fails | Uses the official direct MSIX route | Windows deployment policies and dependencies still apply |
| Connection interrupted | Retries a transient transport failure once | Fix the network if retry fails |
| `0x80073CF4`, `0x80070070`, low storage | Checks space and stops | Free space on the Windows/download drive |
| `0x80073CF3`, dependency conflict | Checks required installed frameworks | Use the official Store installer or IT-provided dependencies |
| `0x80073CFD`, old Windows | Checks OS and manifest requirements | Install applicable Windows updates |
| `0x80073D10`, wrong CPU architecture | Chooses native x64/ARM64 and validates it | A 32-bit OS needs a supported OS/device |
| `0x80073D01`, `0x80073CFF`, policy restrictions | Reports the refusal | Ask the administrator; policies are not changed |
| `0x80070005`, access denied | Explains permissions/policy/security possibilities | Check security-software and Windows events |
| `0x80073D0A`, disabled service errors | Reports selected service states | Restore approved service configuration with IT |
| `0x80072EE7`, DNS | Identifies the lookup failure | Repair the permitted network/DNS configuration |
| `0x80072F8F`, TLS | Refuses an untrusted connection | Check clock, trust store and corporate TLS inspection |
| Signature/digest errors | Refuses installation | Investigate the download and certificate trust |
| Version-specific download returns HTTP `404` | Tries OpenAI's documented download for the same architecture | If both sources fail, retry later; the report preserves the HTTP status |
| HTTP `403`, DNS or TLS failure | Reports the specific failure without changing sources | Check permitted network access, proxy or certificate configuration |
| `RELEASE_CHANNEL_DIFFERENCE` | Reports feed and signed package versions separately; keeps newer installed versions | The feed and downloadable package may differ during publication; check again later |
| `0x80073CF6`, registration failure | Looks for specific codes in recent events | Inspect Windows deployment events if cause remains unknown |
| `0x80073D25`, another user's package | Reports the conflict | Other users may need to save work and sign out |
| `0x80073D26` / `0x80073D27`, service conflict | Stops with advice | Vendor/IT investigation; no service deletion |
| `0x80073CFE`, damaged Windows package database | Stops with repair guidance | Windows support/IT; no automatic registry or repository reset |
| Missing license/entitlement, sign-in, unsupported service region | Cannot grant entitlement or access | Use official installation/account support |
| Unknown error | Preserves its code and reports failure | File a minimal reproducible issue without private data |

## Common questions

### Why doesn't this reset Microsoft Store or reinstall all AppX packages?

Those operations affect unrelated applications and user state. Direct official package installation handles many delivery-path problems without those broad changes. A stopped service with Manual/trigger start is normal and is not automatically diagnosed as broken.

### Why can a report show old errors after a successful update?

The report reads a bounded selection of recent deployment events. Entries marked `historical` describe previous attempts. The installed package and version are checked separately.

### Does this bypass Microsoft Store licensing?

No. Windows continues to enforce signatures, deployment policy, dependencies and any licensing requirements. For a fresh installation that needs offline licensing or all-user provisioning, use [OpenAI's supported enterprise/offline deployment procedure](https://learn.chatgpt.com/docs/enterprise/windows-deployment). This tool uses current-user deployment and does not provision packages to every user.

### Does it fix “unsupported country” after moving from Russia?

No local installer can guarantee that. Review your actual Windows and Microsoft account country after relocating, and check OpenAI's live supported-country list. The tool cannot infer the server-side reason from a Windows region or language setting. See the [region explanation](../README.md#russia-relocation-and-microsoft-store-region).

### Is every Windows/AppX error supported?

No. The catalog is maintained, and unknown errors remain errors. The tool deliberately avoids automatic OS repair, user-data resets, service removal, policy changes and security-control changes. A useful diagnosis is preferable to an unsafe “fix everything” promise.

### Does a green test badge prove installation works on my computer?

No. Unit/workflow tests exercise decisions and mocked deployment. See the documented [validation scope](../CONTRIBUTING.md#validation-scope), and test real installation on a disposable Windows machine before organizational rollout.
