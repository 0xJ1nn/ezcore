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

1. **GitHub Security Advisories** (preferred):
   - Go to the [Security tab](../../security/advisories)
   - Click "Report a vulnerability"
   - Fill in the details privately

2. **Email** (fallback):
   - Send to: security@ezcore.app (if configured) or via GitHub's private vulnerability reporting

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