# ezCORE — Sustainability & Monetization

> **Status: decided** (2026-09-19). This supersedes the earlier draft plan,
> which proposed feature-gating (paywalled save slots, fast-forward, themes).
> That approach is **rejected** — paywalling emulator features ruins the
> experience the project exists for.

## Principles — non-negotiable

1. The app stays **free, open source (GPL-3.0), and fully local**.
2. **Never:** ads, closed-source cores, paywalled features. The free build
   is the complete product — fast-forward, save states, cheats, themes,
   shaders, all of it, forever.
3. Paid options are **additive only**: support, convenience, services.
4. Only the maintainer publishes official builds to any store
   (see [`TRADEMARKS.md`](../TRADEMARKS.md)).

## The model (PPSSPP-style)

### 1. Donations & sponsorships — live now

- **GitHub Sponsors** — [`github.com/sponsors/0xJ1nn`](https://github.com/sponsors/0xJ1nn);
  the `.github/FUNDING.yml` wires the Sponsor button.
- **Sponsors get early access** to features and builds.

### 2. ezCORE Platinum — paid convenience build (planned)

- Google Play, one-time purchase, separate listing and package id
  (`com.ezcore.platinum`) — the PPSSPP Gold pattern: same engine as the
  free build, premium icon/theme, and a direct way to fund development.
- Selling GPL-3.0 binaries is fine (the source is public); buyers get the
  same source rights as everyone.
- **License rule:** a paid build bundles only cores whose licenses permit
  commercial distribution. Non-commercial cores (Snes9x, Genesis Plus GX)
  are never bundled in any build — enforced by
  [`scripts/license_audit.py`](../scripts/license_audit.py).

### 3. ezCORE Cloud — sync & backup (planned, v1.1+)

- Optional subscription. You pay for the **service** — servers, storage,
  version history — not for software features.
- Local saves stay complete for free; sync is a convenience on top.

## Cost posture

| Phase | Monthly cost | Covered by |
|---|---|---|
| v0.1.x (local-only) | $0 | GitHub hosting |
| Cloud (v1.1+) | servers + storage | the subscription |

## Permanently out of scope

Ads · cosmetic IAP · closed cores · paywalls · selling user data ·
region-locking.
