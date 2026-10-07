# Releasing ezCORE

Maintainer guide. Two supported paths: **local assembly** (used when CI is
unavailable, and for the first release) and the **CI workflow**
(`.github/workflows/release.yml`, manual dispatch). Both produce the same
artifact names, checksums, and notes file.

---

## Versioning

- `pubspec.yaml` carries `version: X.Y.Z+N`. `scripts/release.sh` reads the
  `X.Y.Z` part for artifact names; the release tag is `vX.Y.Z`.
- While pre-1.0, treat every release as an early build: the notes say so
  explicitly.

## Release notes

Notes live in the repo at `.github/release-notes/<tag>.md` (e.g.
`.github/release-notes/v0.1.0.md`). Both release paths attach this file to
the GitHub Release. Keep the house style:

1. One-paragraph honest summary (what this is, what changed).
2. `What's in this build` — platforms + counts.
3. `Known limitations` — the parts that don't work yet. Never omit this.
4. `Verifying your download` — sha256 lines.
5. `Reporting` — issues + PRs, with the "early build" reminder.

## Secrets (for signed/notarized/CI releases)

| Secret | Purpose |
|---|---|
| `EZCORE_KEYSTORE_BASE64` | `base64 -i ezcore-release.keystore` — Android release signing |
| `EZCORE_KEYSTORE_PASSWORD` | keystore password |
| `EZCORE_KEY_ALIAS` | key alias (default `ezcore`) |
| `EZCORE_KEY_PASSWORD` | key password |
| `EZCORE_CODESIGN_IDENTITY` | optional — macOS notarization identity (`Developer ID Application: …`) |

Set with `gh secret set <name>` (or repo Settings → Secrets). The local
keystore file and its credentials are **never committed** (`.gitignore`
covers `*.keystore`, `*.jks`, `key.properties`); keep an offline copy of the
keystore — losing it means you cannot update the Android app with the same
identity.

## Local release (what v0.1.0 used)

```bash
# 0. clean tree, gates green
python3 scripts/fill_manifest_data.py --check
python3 scripts/build_catalog.py
python3 scripts/license_audit.py
python3 scripts/verify_core_art.py
flutter analyze && flutter test
flutter test --no-pub test/hardware_art_test.dart

# 1. per-platform artifacts (repeat per platform)
scripts/release.sh macos  --out dist/          # needs full macOS tier staged
EZCORE_KEYSTORE_FILE="$PWD/ezcore-release.keystore" \
EZCORE_KEYSTORE_PASSWORD=… EZCORE_KEY_ALIAS=ezcore EZCORE_KEY_PASSWORD=… \
  scripts/release.sh android --out dist/       # needs android tier staged

# 2. checksums
(cd dist && shasum -a 256 ezcore-* > SHA256SUMS.txt)

# 3. publish (notes file from .github/release-notes/<tag>.md)
gh release create v0.1.0 \
  --title "v0.1.0 — first public build" \
  --notes-file .github/release-notes/v0.1.0.md \
  dist/ezcore-0.1.0-macos-arm64.zip \
  dist/ezcore-0.1.0-android-arm64.apk \
  dist/SHA256SUMS.txt
```

`scripts/release.sh` refuses to assemble a release unless: manifests are
policy-clean (`fill_manifest_data --check`), the license and artwork provenance
audit passes, every bundled WebP decodes, the banned-content scan passes, the
staged cores match the committed pins, and the bundle is rebuilt for the target
OS. The artwork gate covers the exact flat `assets/core_art/` set, not just
files ending in `.webp`. It also bundles **exactly** the cores whose manifest
`delivery` promises `bundled` for that OS — held cores stay out even when
staged.

### macOS signing & pins (read this before touching codesign)

- macOS staged artifacts are **ad-hoc signed at stage time** and the pins
  describe those signed bytes. Ad-hoc signatures are not reproducible, so
  **never sign after pinning** and never re-sign a pinned artifact —
  `pin_artifacts` will (correctly) fail and the app will refuse to stage.
- During bundling, `release.sh` signs only the runtime dylib
  (`Contents/Frameworks/`) and the app itself (with
  `macos/Runner/Release.entitlements`). The core dylibs in
  `Contents/Resources/` are **not** signed again — that would break the pins
  the app verifies before staging. Resources/ nested code does not require a
  signature, and the ad-hoc path has no hardened runtime, so `dlopen` works.
- For a future notarized build: hardened runtime + library validation needs
  either the `disable-library-validation` entitlement or cores signed with
  the same team ID **and re-pinned to the signed bytes** (one build → sign →
  pin → ship, no re-signing).

## CI release

Actions → **Release** → *Run workflow*:

- `version`: the tag to create (e.g. `v0.1.1`)
- `platforms`: comma-separated subset of `macos,windows,linux,android`
  (default all four; iOS is intentionally absent — no signing identity yet)

The workflow builds each platform, uploads artifacts, then creates the
GitHub Release with the notes file for that tag (or generated notes when no
file exists). **Current caveat:** CI is not running on this repo yet —
check `gh run list` first; until a green run exists, use the local path
below (and see the branch-protection note at the bottom of this file).

## Post-release checklist

- [ ] Release page shows every expected artifact + `SHA256SUMS.txt`
- [ ] Notes state the honest limitations (platforms, verified cores)
- [ ] `CHANGELOG.md` updated and committed
- [ ] `docs/MATRIX.md` reflects what actually shipped
- [ ] Discussions/issue templates still point at the right docs
- [ ] Offline keystore backup confirmed (Android)

## Branch protection (temporary state)

`main` still protects against force-pushes and deletions and asks for one
review on PRs. The six CI checks (`ci/dart-gates`, `ci/native-linux`,
`ci/macos`, `ci/windows`, `ci/android`, `ci/ios`) are **not currently
required** — they cannot report while CI is not running, and
required-but-never-reported checks would block every PR. Re-enable them
once CI runs again:

```bash
gh api -X PUT repos/0xJ1nn/ezcore/branches/main/protection/required_status_checks \
  -F strict=true \
  -f 'contexts[]=ci/dart-gates' -f 'contexts[]=ci/native-linux' \
  -f 'contexts[]=ci/macos' -f 'contexts[]=ci/windows' \
  -f 'contexts[]=ci/android' -f 'contexts[]=ci/ios'
```

Also re-add the CI badge to the README (first badge in the badge row) when
green runs exist, and re-enable the workflows (they are disabled while CI
cannot run — Actions tab → *Enable workflow*, or):

```bash
for wf in ci.yml matrix.yml release.yml labeler.yml; do
  gh workflow enable "$wf" --repo 0xJ1nn/ezcore
done
```
