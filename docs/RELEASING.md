# Releasing ezCORE

A release is a repeatable loop: choose a target, land the work with its
changelog entry, verify a candidate, then tag and publish. This page records the
version scheme and who does each step. The rules apply to the app and to core
sets, which are versioned separately.

## Version scheme

The app uses semantic versions of the form `MAJOR.MINOR.PATCH` and is tagged
`vX.Y.Z`. A patch release fixes defects without changing how the app works. A
minor release adds features or systems while keeping existing saves and settings
usable. A major release marks a change in the product's public shape.

Core sets use their own calendar versions, `cores-YYYY.MM.N`, for example
`cores-2026.12.1`. The third number separates more than one set in a month. A
core set changes when a core recipe, pin, build or catalogue entry changes; it
does not need a new app version. Desktop and directly downloaded Android builds
pick up a new core set from the published index. Bundled platforms pick it up
with the next app release, because their cores ship inside the signed app.

The release sequence follows the product milestones. The first release,
**v0.3.0**, is the games-play milestone: the native player and the play checks
land on Android and Linux. **v0.4.0** adds the first core set and the shared core
delivery pipeline. **v1.0.0** is the public launch on the stores and as desktop
downloads. Each release takes its scope from the matching milestone; work that
is not ready moves to the next one rather than delaying the current release.

## The release loop

1. **Choose the target.** The maintainer names the milestone and the systems or
   features in scope. Anyone may propose work by opening an issue; nothing ships
   from an unrecorded request.
2. **Land the work.** A contributor makes the change, adds one line under
   `## [Unreleased]` in `CHANGELOG.md` naming the platforms it affects, such as
   `[android, ios]`, and opens a pull request. The change and its changelog line
   land together. A change to `lib/`, `runtime/`, `cores/` or a platform
   directory without a new unreleased entry is rejected by the repository
   hygiene gate. Documentation, tests and tooling need no entry.
3. **Review and merge.** Automated checks run on the exact pull request head:
   repository hygiene, the changelog gate, the public-text audit, static
   analysis and the test suite. A reviewer reads the diff and the evidence, then
   the maintainer merges. Contributors do not merge their own work, and nothing
   is merged with failing checks.
4. **Prepare a candidate.** When the scope is closed, the maintainer runs the
   play sweep on every available device and the release checklist. Release
   builds are assembled with `scripts/release.sh <platform>` for each target
   that can be built here. Signed Apple archives, store uploads and notarisation
   need the maintainer's credentials and a machine with the Apple toolchain.
   Evidence belongs to the target it was gathered on; a passing desktop build
   says nothing about iOS or Android.
5. **Check the notes.** `scripts/release.sh --notes` prints the current
   `## [Unreleased]` section as draft release notes. Read them before tagging:
   they are the text players will see, and they must describe the shipped change
   rather than the work that produced it.
6. **Tag and publish.** Only the maintainer may cut a release. Move the
   Unreleased section into a dated version section, tag the app `vX.Y.Z` and the
   core set `cores-YYYY.MM.N` when one ships, then publish the artifacts and the
   release. Store submissions and public announcements are maintainer actions.
7. **Look back.** Anything found while preparing the candidate becomes work for
   the next milestone. Start the loop again with that milestone as the target.

## Who may do what

| Step | Contributor | Maintainer |
|---|---|---|
| Propose work and describe a target | Yes | Yes |
| Implement, document and test a change | Yes | Yes |
| Add the changelog line and open a pull request | Yes | Yes |
| Review and merge | No | Yes |
| Cut, tag and publish a release, sign builds, upload to stores | No | Yes |
| Change repository settings, licences or visibility | No | Yes |

Core sets follow the same loop with their own tag. A core set may be published
between app releases when only the published core index changes; bundled
platforms wait for the next app release by design.
