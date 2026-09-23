# Pull Request Template

## Summary
<!-- One-line description of what this PR does -->

## Type of Change
<!-- Check all that apply -->
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Core version bump / new core addition
- [ ] Documentation update
- [ ] CI/build infrastructure
- [ ] Refactor / code cleanup (no functional change)
- [ ] Performance improvement

## Related Issues
<!-- Link issues this PR addresses -->
- Closes #
- Fixes #
- Related to #

## Changes Made
<!-- Bullet list of key changes -->
- 

## Testing
<!-- How did you verify this works? -->
- [ ] `flutter analyze` passes (no new issues)
- [ ] `flutter test` passes (all existing tests + new tests for new code)
- [ ] Manual testing on: macOS / Windows / Linux / Android / iOS (check all that apply)
- [ ] Core matrix test: `flutter test test/core_matrix_test.dart` (if core-related)
- [ ] Native CTest: `cd runtime/build-<os> && ctest` (if runtime-related)
- [ ] Banned content scan: `bash scripts/banned_content_scan.sh` passes

## Screenshots / Recordings
<!-- For UI changes, include before/after screenshots or screen recordings -->

## Core Changes (if applicable)
<!-- For core version bumps or new cores -->
- Core: 
- Upstream commit/tag: 
- License: 
- Systems: 
- SHA256 pins updated in `cores/<id>/manifest.json` for: macos-arm64 / windows-x64 / linux-x64 / android-arm64 / ios-arm64
- `scripts/fill_manifest_data.py` run (execution/delivery/cheats policy updated)
- `scripts/pin_artifacts.py` run for all target platforms
- `scripts/build_catalog.py` run (catalog.json updated)

## Licensing (required for all PRs)
- [ ] No ROMs, BIOS/firmware, keys, or game files added (CONTRIBUTING.md rule 1)
- [ ] No cheat databases added (CONTRIBUTING.md rule 2)
- [ ] No circumvention tooling added (CONTRIBUTING.md rule 3)
- [ ] No Nintendo/Sony/Sega trademarks in code, assets, or copy (CONTRIBUTING.md rule 4)
- [ ] No Switch/3DS/PS2 core changes (CONTRIBUTING.md rule 5)
- [ ] All new code has DCO sign-off: `git commit -s`

## Checklist
- [ ] My code follows the project's style (flutter analyze clean)
- [ ] I have added tests that prove my fix/feature works
- [ ] New and existing tests pass locally
- [ ] I have updated documentation if needed (README, docs/, code comments)
- [ ] Commit messages follow Conventional Commits (`feat:`, `fix:`, `refactor:`, etc.)
- [ ] Commits are signed off (`git commit -s`)
- [ ] PR title follows Conventional Commits format

## Reviewer Notes
<!-- Any specific areas you want reviewers to focus on, or context about the implementation -->