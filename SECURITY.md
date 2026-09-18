# Security Policy

## Supported Versions

We only provide security updates for the latest release.

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| Older   | :x:                |

## Reporting a Vulnerability

**Do not open a public issue** for security vulnerabilities.

Instead, please report them via one of these channels:

1. **GitHub private vulnerability reporting** (preferred):
   - Go to the [Security tab](../../security) → "Report a vulnerability"
   - This opens a private advisory visible only to maintainers
2. **Fallback:** if private reporting is unavailable to you, open a
   minimal public issue that says only "security — request private
   channel" (no details), and a maintainer will follow up privately.

## What to Include

Please provide:
- Description of the vulnerability
- Steps to reproduce or proof-of-concept
- Affected versions/platforms
- Potential impact (data exposure, code execution, etc.)
- Any suggested fixes

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Fix target**: Critical/high severity — next patch release; medium/low — next minor release

## Scope

This policy covers:
- ezCORE app shell (Flutter/Dart)
- ezCORE native runtime (C/FFI)
- Core build scripts and manifest handling
- Android/iOS platform integrations

It does **not** cover:
- Upstream libretro cores (report to their respective projects)
- User-supplied ROMs/BIOS/games (out of scope)
- Third-party dependencies (report to their maintainers)

## Disclosure

We follow coordinated disclosure. Once a fix is released, we will publish a Security Advisory with CVE if applicable.