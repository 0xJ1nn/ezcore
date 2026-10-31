# Licensing policy

**Decided 2026-10-31.** This page is the single source of truth for which
licence applies to which part of ezCORE, and why. The reasons appear in plain
language so that a contributor, a packager or a company can check their own
case. It is a policy, not legal advice to you.

## What is under which licence

| Part | Licence |
|---|---|
| The app and runtime (this repository) | **GPL-3.0-only**, with the [Core Module Exception](../LICENSE-EXCEPTION.md) |
| Runtime host API header (`ezcore-core-api`) | GPL-3.0-only |
| Third-party emulator cores | each core's upstream licence, unchanged |
| Cores you write yourself | **any licence you choose**, including proprietary |
| First-party core packages in official builds | proprietary; shipped only inside official ezCORE builds |
| Fonts, art | as noted per file (e.g. OFL-1.1 for fonts; `CORE_ART_PROVENANCE.md`) |

### Why GPL with a core-module exception

The GPL keeps ezCORE itself open: anyone who ships a modified ezCORE must
publish their changes under the same terms. The Core Module Exception keeps
the **core ecosystem** open to everyone. A core that talks to ezCORE through
libretro or the ezCORE package interface can be under any licence, so
independent developers, companies and the project itself can all build and
ship cores without their core becoming GPL.

### Build your own cores

You are welcome to build cores for ezCORE and to publish them under your own
name and licence. Say that your core "works with ezCORE"; do not call it
ezCORE or use the logo ([`TRADEMARKS.md`](../TRADEMARKS.md)). The authoring
guide is [`CORE_AUTHORING.md`](CORE_AUTHORING.md). A core that includes
third-party emulator code must also follow that code's licence: a GPL
emulator stays GPL.

### Official builds

Official ezCORE builds are published only by the maintainer, through this
repository's Releases and the official store listings. They may contain
proprietary first-party core packages. Those packages are not covered by the
GPL, are not part of this repository, and may not be extracted or
redistributed. The GPL source of the app itself remains available here.

## Compatibility rules (enforced by `scripts/license_audit.py`)

- A **GPL-2.0-only** core is never bundled with the GPL-3.0-only app.
- A **non-commercial** core (Snes9x, Genesis Plus GX, FBNeo) is never
  bundled or downloaded by any build. Users may build it themselves.
- A paid build bundles only cores whose licences permit commercial
  distribution.
- A proprietary core is never linked with, or built from, third-party GPL
  code.

## Contributions (inbound licence)

- Every contributor signs the [CLA](../CLA.md) and signs off commits (DCO).
- The CLA is a **licence, not a copyright assignment**. It lets the
  maintainer ship official builds under the terms the stores require and keep
  the Core Module Exception consistent. In return it **promises** that the
  open-source app always stays available and is never made less capable to
  sell a paid one (CLA §3).
- AI-assisted work is disclosed (`Assisted-by:` / `Co-Authored-By:`) and
  reviewed by the human who submits it (CLA §5.4, `CONTRIBUTING.md`).

## The name and the logo

No code licence grants any right to the ezCORE name, logo or brand assets.
The GPL lets anyone share the app's source code; it does not let anyone
distribute their build **as ezCORE**. A fork must use its own name and icon,
and official ezCORE builds may not be mirrored or repackaged. See
[`TRADEMARKS.md`](../TRADEMARKS.md).

## Open legal questions (tracked, not hidden)

1. Governing law and venue for the CLA (CLA §9).
2. How much copyright protection AI-generated code receives in the
   jurisdictions where ezCORE is distributed.
3. Trademark registration (filing is pending; until registration, the marks
   are used with ™, never ®).
