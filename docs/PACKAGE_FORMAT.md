# ezCORE Package Format v1

> **Enforcement.** This format is enforced by `lib/services/core_package_validator.dart` as of 2026-09-29. The format draft, install contract, trust labels, and the design invariant that *package data never executes code* are defined in `EZCORE-PACKAGE-PLATFORM-MASTER-PROMPT.md` §3–§4.

## 1. What a package is

A package is a directory (or a zip of one) that bundles a single libretro core together with its validated metadata. A package is self-contained and operates fully offline — no account, telemetry, or network access is required to install or run it.

The directory name MUST equal the core's `id` field (see §2). The on-disk shape is:

```
<core-id>/
  manifest.json               # validated, versioned source of truth
  <core-id>.so|.dylib|.dll    # the core library (platform-specific suffix)
  info/
    <core-id>.info             # libretro metadata — parsed, never executed
  options/                     # RESERVED for future use — not parsed by v1
  layouts/                     # RESERVED for future use — not parsed by v1
  cheats/                      # RESERVED for future use — not parsed by v1
```

The `<core-id>.info` file is a libretro core-info file: plain-text, line-oriented metadata parsed by `lib/services/retro_info_parser.dart`. It is never executed as code. Its grammar is `key = "value"` per line; lines beginning with `#` are comments; a trailing backslash (`\`) joins a logical line across the next physical line; and inside a quoted value, `\"` and `\\` are the only escapes. Unknown keys are preserved for callers.

**Design invariant.** Everything in a package that is not the core library itself is data: schema-validated, size-capped, path-confined, containing no symlinks and no fetched URLs (`EZCORE-PACKAGE-PLATFORM-MASTER-PROMPT.md` §2.3).

The `options/`, `layouts/`, and `cheats/` directories are reserved for future use and are not parsed or enforced by v1. They are data-only by design.

## 2. The manifest schema

`manifest.json` is a single JSON object at the root of the package directory. The set of accepted top-level keys is fixed (see §3 for enforcement); any key not listed in §2.1 is REJECTED.

### 2.1 Field reference

| Field | Type | Required | Enforcer |
|---|---|---|---|
| `id` | string | validator | Core identifier |
| `name` | string | catalog | Human-readable name |
| `version` | string | catalog | Core version (e.g. `"0.9.9"`) |
| `license` | string | catalog | SPDX expression |
| `license_url` | string | optional | URL to license text |
| `homepage` | string | optional | Project homepage |
| `upstream` | string | optional | Upstream repo path |
| `systems` | string[] | catalog | System identifiers the core runs |
| `extensions` | string[] | optional | File extensions accepted |
| `cheats_supported` | bool | optional | Cheats support flag |
| `cheat_families` | string[] | optional | Cheat family identifiers |
| `delivery` | object | catalog + model | Per-OS delivery strategy |
| `artifacts` | object | optional | Per-platform sha256 pins |
| `execution` | object | optional | OS → execution strategy |
| `bios_required` | bool | optional | BIOS needed flag |
| `bios_files` | string[] | optional | Expected BIOS filenames |
| `bios_notes` | string | optional | Human-readable BIOS guidance |
| `provenance` | object | optional | Build provenance metadata |
| `blocked_reason` | string | optional | Legal/IP hold explanation |
| `gated_reason` | string | optional | License gate explanation |
| `notes` | string | optional | Free-form operator notes |

The known top-level field set is fixed at these 20 keys by the validator (`kKnownManifestFields`). No other top-level key is accepted, including a `signature` field (see §5.1).

**Required-field summary:**

- The *validator* requires only `id` (presence, format, directory match — §3).
- The *catalog merger* (`scripts/build_catalog.py`) additionally requires `name`, `version`, `license`, `systems`, and `delivery` to be present (§4.5).
- The *app-side model* (`lib/models/core_manifest.dart`) requires `id`, `name`, `version`, `license`, and `systems` to be non-empty at runtime.

### 2.2 Field semantics

**`id`** — The core's stable identifier. MUST match `^[a-z0-9_]+$` and MUST equal the package directory name. For hold cores the directory carries a `_hold` suffix (e.g. `citra_hold`); the validator still requires exact `id`–directory match, so the `id` field itself bears the suffix.

**`artifacts`** — Maps a platform-architecture identifier (`macos-arm64`, `linux-x64`, `android-arm64`, `windows-x64`, `ios-arm64`) to a 64-character lowercase hexadecimal SHA-256 pin of the exact core library bytes. A manifest with `blocked_reason` MUST have an empty `artifacts` object (`{}`).

**`delivery`** — Maps a platform identifier (`macos`, `windows`, `linux`, `android`, `ios`) to one of `bundled`, `download`, or `absent` (§3.5). iOS MUST never be `download` (App Store Review 2.5.2/4.7) — this constraint is enforced by the model and the catalog, not the validator.

**`execution`** — Maps a platform identifier to `interpreter` or `dynarec`. Absent entries mean "unknown." iOS MUST never resolve to `dynarec` (no JIT on the App Store) — enforced by the model. The validator does not inspect `execution` values.

**`provenance`** — An object with `built_from` (string, source repo URL), `upstream_license` (string), `relationship` (string), and an optional `modifications` (string).

**`bios_required` / `bios_files` / `bios_notes`** — Document BIOS dependencies (§6). The project never ships BIOS; these fields only name what the user must supply.

**`blocked_reason`** — Present only on hold cores. The value is a human-readable explanation of the legal or IP block. A core with `blocked_reason` MUST NOT carry artifacts (§4.5, §3 note).

**`gated_reason`** — Present only on license-gated cores. A gated core builds but has `delivery: absent` on every platform and is never shipped.

### 2.3 The three real shapes

The tables below show the distinguishing fields across the three manifest shapes committed in this repository. Full files: `cores/nesbyte/manifest.json`, `cores/gambatte/manifest.json`, `cores/citra_hold/manifest.json`.

**Bundled core — `cores/nesbyte/manifest.json`**

| Field | Value |
|---|---|
| `id` / `name` | `nesbyte` / `NesByte` |
| `version` | `0.9.9` |
| `license` | `GPL-3.0` |
| `systems` | `["nes", "fds"]` |
| `delivery` | all platforms: `bundled` |
| `artifacts` | 3 pins (`macos-arm64`, `android-arm64`, `linux-x64`) |
| `execution` | all platforms: `interpreter` |
| `bios_required` | `false` |
| `bios_files` | `["disksys.rom"]` |
| `bios_notes` | `"FDS only, optional. User-supplied."` |
| `provenance` | present (`built_from`, `upstream_license`, `relationship`) |
| `blocked_reason` | absent |
| `gated_reason` | absent |

**Gated core — `cores/gambatte/manifest.json`**

| Field | Value |
|---|---|
| `id` / `name` | `gambatte` / `Gambatte` |
| `version` | `0.5.0` |
| `license` | `GPL-2.0-only` |
| `systems` | `["gb", "gbc"]` |
| `delivery` | all platforms: `absent` |
| `artifacts` | 3 pins (`macos-arm64`, `android-arm64`, `linux-x64`) |
| `execution` | all platforms: `interpreter` |
| `bios_required` | `false` |
| `bios_files` | `[]` |
| `provenance` | present (`built_from`, `upstream_license`, `relationship`, `modifications`) |
| `gated_reason` | `"GPL-2.0-ONLY upstream…cannot form a combined work with the GPL-3.0-only app"` |
| `blocked_reason` | absent |

**Hold core — `cores/citra_hold/manifest.json`**

| Field | Value |
|---|---|
| `id` / `name` | `citra_hold` / `Nintendo 3DS — on hold` |
| `version` | `0.0.0-blocked` |
| `license` | `GPL-2.0 (upstream tainted — do not build from post-2024 forks)` |
| `systems` | `["3ds"]` |
| `extensions` | `[]` |
| `delivery` | all platforms: `absent` |
| `artifacts` | `{}` (empty) |
| `execution` | absent |
| `bios_required` | `true` |
| `bios_files` | `[]` |
| `blocked_reason` | Legal hold: Citra takedown, DMCA 1201 exposure |
| `gated_reason` | absent |
| `provenance` | absent |

> **Note on `citra_hold`.** `bios_required: true` with `bios_files: []` triggers a non-fatal validation warning (§3.6) — the core declares it needs BIOS but does not name expected files. This is acceptable for a hold core: the core is never built or shipped, so the warning is informational.

## 3. The validation contract

Every rule below is enforced by `lib/services/core_package_validator.dart`. A package that violates any rule marked **MUST** fails validation (`PackageValidationReport.ok` is `false`). The validator collects all problems into `errors` and `warnings` — it MUST NOT throw for policy failures. `errors` are hard fails; `warnings` are advisory and do not affect `ok`.

### 3.1 Manifest existence and parseability

1. The package directory MUST contain a `manifest.json` file at its root. If the file is missing or unreadable, validation fails.
2. `manifest.json` MUST be valid JSON. If it does not parse, validation fails.
3. The JSON root MUST be a JSON object. Any other JSON type fails validation.
4. `manifest.json` MUST NOT exceed 1 MiB (`defaultMaxManifestBytes`). The size is measured on the raw file bytes; oversize fails validation.

### 3.2 Top-level field set

5. Every top-level key in `manifest.json` MUST be one of the 20 known fields. Any unrecognized key is REJECTED. This is the forward-safety mechanism described in §7. (The known set is `id`, `name`, `version`, `license`, `license_url`, `homepage`, `upstream`, `systems`, `extensions`, `cheats_supported`, `cheat_families`, `bios_required`, `bios_files`, `delivery`, `artifacts`, `execution`, `bios_notes`, `provenance`, `blocked_reason`, `gated_reason`, `notes`.)

### 3.3 Identifier

6. `id` MUST be present and a non-empty string.
7. `id` MUST match the regular expression `^[a-z0-9_]+$`.
8. `id` MUST equal the package's directory name.

### 3.4 Artifact pins

9. If `artifacts` is present, it MUST be a JSON object.
10. Every value in the `artifacts` object MUST match `^[0-9a-f]{64}$` — a 64-character lowercase hexadecimal string.

### 3.5 Delivery

11. If `delivery` is present, it MUST be a JSON object.
12. Every value in the `delivery` object MUST be one of `bundled`, `download`, or `absent`. The value `on-demand` MUST NOT appear — the validator rejects it by design; it was a brief invention with no consumer.

### 3.6 BIOS (non-fatal)

13. If `bios_required` is `true` and `bios_files` is absent, not a list, or empty, the validator SHOULD emit a warning. This is non-fatal: validation still passes (`ok` remains `true`).

### 3.7 Package tree scan

14. The validator MUST recursively walk the entire package tree with symlinks disabled (`followLinks: false`).
15. The total byte size of all files in the package tree MUST NOT exceed 512 MiB (`defaultMaxPackageBytes`). Oversize fails validation.
16. The package tree MUST NOT contain any symlink. A symlink at any path — file or directory — is REJECTED. The scan detects symlinks but does not follow them (§1 design invariant).

### 3.8 Validation result

17. The validator MUST return a `PackageValidationReport` with `ok` set to `true` only when `errors` is empty. `warnings` never affect `ok`.

> **Scope note.** The validator enforces on-disk shape rules only (§3.1–3.8). It does NOT check `name`, `version`, `license`, `systems`, or `delivery` presence, nor does it enforce the iOS `download` ban, the `execution` value set, or the blocked-core-no-artifacts invariant. Those are enforced by the catalog merger (§4.5) and the app-side model (`lib/models/core_manifest.dart`, see §8).

## 4. The install contract

Installation is a six-stage pipeline. The entire pipeline is offline-only: no network access is required or used at any stage.

1. **Parse.** The libretro `.info` file (if present) is parsed by `lib/services/retro_info_parser.dart`. Parsing is lenient — malformed input produces warnings on the returned `RetroInfo` object, never exceptions. Unknown keys are preserved.
2. **Validate.** The package is validated per §3. A package that fails validation (`ok == false`) is rejected before any staging occurs.
3. **Pin-verify.** The SHA-256 of the actual core library bytes is compared against the `artifacts` pin for the current platform. The validator checks that pin *values* are well-formed hex (§3.4); pin *matching* is performed separately by `scripts/pin_artifacts.py --check`. A mismatch fails the install.
4. **Consent.** Installing a package adds native code to the device. Per `EZCORE-PACKAGE-PLATFORM-MASTER-PROMPT.md` §2.4, this MUST require the user's explicit consent in the UI. The trust level (§5) MUST be stated plainly at the consent prompt. Native code is never staged silently.
5. **Stage.** The package is copied into the user's vault. The directory scan (§3.7) is re-applied during staging — symlinks and oversize are rejected.
6. **Register.** The package is registered into the runtime catalog via `scripts/build_catalog.py`, which enforces the invariants in §4.5.

If any stage fails, installation aborts immediately and no files are staged into the vault.

### 4.5 Catalog invariants (enforced at registration)

The catalog merger (`scripts/build_catalog.py`) enforces these before a package enters the runtime catalog:

17. `id`, `name`, `version`, `license`, `systems`, and `delivery` MUST all be present (`REQUIRED` set).
18. `id` MUST match the directory name. For directories ending in `_hold`, the match is relaxed — the id may omit the suffix.
19. No two packages in the catalog MAY share an `id`.
20. iOS delivery MUST NOT be `download`.
21. A core with `blocked_reason` MUST NOT carry artifacts.

## 5. The trust model

Two trust labels exist:

- **ezCORE Verified.** The core has passed review (pin match, license audit, delivery consistency). Verified cores MAY be offered as defaults and appear in the built catalog.
- **Unverified.** The core is labelled and opt-in only. The user MUST explicitly acknowledge the trust status before installation. Unverified cores are never auto-updated.

A package's trust label is determined at build/catalog time, not at install time. The label is immutable in the catalog — the application MUST NOT silently reclassify a core.

### 5.1 Signature

The `signature` field is reserved for P7 (real package signing). In v1, `signature` is NOT one of the known manifest fields (§2.1) and including it causes validation rejection (§3.2). The conceptual slot is `dev-unsigned` until P7 lands. Never hand-roll crypto.

### 5.2 Hold cores

A core with `blocked_reason` is under a legal or IP hold. It MUST NOT be staged with artifacts, MUST NOT be shipped, and `scripts/pin_artifacts.py` refuses to pin it (see `docs/CORE_AUTHORING.md` §3.3). The build recipe is retained as an architecture slot only — `build_core.sh` exits with code 4 for hold cores.

### 5.3 Gated cores

A core with `gated_reason` is license-gated. It builds but has `delivery: absent` on every platform and is never distributed in any binary. A GPL-2.0-only core, for example, cannot form a combined work with the GPL-3.0-only app shell when linked as a bundled plugin — this is why `gated_reason` exists (see `docs/CORE_AUTHORING.md` §3.3).

## 6. The BIOS rule

Packages MAY declare `bios_required`, `bios_files`, and `bios_notes` to document which BIOS images a core needs. The ezCORE project NEVER ships, fetches, or bundles BIOS or ROM files — not in the repository, not at runtime, not in any download. BIOS images are user-supplied: the user dumps them from hardware they own and places them in the app's system directory. A package's `bios_files` list declares expected filenames only; it does not distribute content.

A package that declares `bios_required: true` SHOULD also declare `bios_files` listing the expected filenames. The validator emits a non-fatal warning when it does not (§3.6). This warning is advisory: it tells the user which files to supply without failing the package.

## 7. Versioning and forward compatibility

This document specifies package format v1. v1 does not define a `format_version` field — that field is reserved for v2, when it will allow consumers to detect and reject future formats.

Until v2 lands, forward safety is provided by unknown-field rejection (§3.2): any top-level key not in the v1 known set is REJECTED. This ensures that a package carrying a field unknown to a v1 consumer fails validation rather than being silently misinterpreted.

The core `version` field is the core's own version (e.g. `"0.9.9"`), not the package format version. The package format version and the core version are independent.

## 8. Normative references

This specification is enforced by and must be read alongside these files:

| File | Enforced rules |
|---|---|
| `lib/services/core_package_validator.dart` | §3. Manifest existence, JSON parse, root type, size caps (§3.1); known field set (§3.2); `id` regex `^[a-z0-9_]+$` and directory match (§3.3); artifact pin format `^[0-9a-f]{64}$` (§3.4); delivery vocabulary `bundled\|download\|absent` (§3.5); BIOS warning (§3.6); package size cap and symlink rejection (§3.7). |
| `EZCORE-PACKAGE-PLATFORM-MASTER-PROMPT.md` | §3 (format draft, install contract, trust labels, signature slot); §2.3 (data-never-executes invariant); §2.4 (opt-in native code). |
| `lib/models/core_manifest.dart` | iOS delivery rule (never `download`); execution strategy (`interpreter\|dynarec`, iOS never `dynarec`); blocked-core-no-artifacts invariant; required-field checks at runtime. |
| `lib/services/retro_info_parser.dart` | `.info` file grammar (`key = "value"`, `#` comments, `\` continuation, `\"`/`\\` escapes); lenient parsing with warnings. |
| `scripts/build_catalog.py` | §4.5. REQUIRED field set, id–directory match (with `_hold` exception), no duplicate ids, iOS `download` rejection, blocked-artifact rejection; writes `cores/catalog.json` and `cores/release.json`. |
| `scripts/fill_manifest_data.py` | Single-writer for `execution`, `cheats_supported`, `cheat_families`, and `delivery` policy fields. |
| `scripts/pin_artifacts.py` | Pin verification (`--check`) and writing; refuses to pin blocked cores. |
| `docs/CORE_AUTHORING.md` | §2.1–§2.3 (schema, field types, validator rules, delivery vocabulary, hold/gated policy, catalog merge); §4 (full verification pipeline). |

---

## Verification

The following files were read and checked against this specification:

- **`EZCORE-PACKAGE-PLATFORM-MASTER-PROMPT.md`** — §3: format draft (directory shape, manifest fields, delivery vocabulary, signature slot, install contract, trust labels). §2.3: data-never-executes invariant. §2.4: opt-in native code consent. §4: crash containment.
- **`lib/services/core_package_validator.dart`** — `kKnownManifestFields` (L25–49, 20 fields); `_idRegex` (L156); `_pinRegex` (L157); `_allowedDelivery` = `{bundled, download, absent}` (L162–166, rejects `on-demand` by design L158–161); `validate()` id presence (L182), id regex (L185), id–dir match (L188–195); artifact pin check (L199–214); delivery check (L217–232); BIOS warning (L234–242); manifest size cap `defaultMaxManifestBytes` = 1 MiB (L78, L127–131); package size cap `defaultMaxPackageBytes` = 512 MiB (L75, L270–277); symlink rejection via `Link` with `followLinks: false` (L255–261); error/warning collection model (L56–153).
- **`cores/nesbyte/manifest.json`** — bundled core reference shape; `delivery: bundled` on all platforms; 3 artifact pins; `bios_files: ["disksys.rom"]`; provenance present.
- **`cores/gambatte/manifest.json`** — gated core; `gated_reason` present; `delivery: absent` on all platforms; 3 artifact pins despite being gated.
- **`cores/citra_hold/manifest.json`** — hold core; `blocked_reason` present; `artifacts: {}`; `bios_required: true` with `bios_files: []` (triggers §3.6 warning); `execution` absent.
- **`lib/services/retro_info_parser.dart`** — `.info` grammar: `key = "value"` (L9), `#` comments (L148), `\` line continuation (L101–106, `_isContinuation` L134–142), `\"`/`\\` escapes (L186–198), lenient parse (L93–129), typed getters (`corename`, `systemname`, `supported_extensions`, `firmware_count`, L49–86).
- **`lib/models/core_manifest.dart`** — Model fields (L7–42); `delivery` iOS rule in `toJson` note (L87–88) and `validate()` (L106–108); execution `interpreter\|dynarec` (L40–42, L112–119); blocked-core-no-artifacts (L109–111); required-field checks in `validate()` (L100–105).
- **`docs/CORE_AUTHORING.md`** — §2.1 field reference table (L136–156); §2.2 validator rules (L168–190); §2.3 delivery vocabulary (L240–255); §3.3 hold/gated/recipe-only (L267–287); §4 catalog merge (L289–316); §2 field types and platform-arch keys (L132–166)