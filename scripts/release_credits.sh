#!/usr/bin/env bash
# Print the Credits section for a release: every GitHub user whose pull
# request was merged since the previous tag, plus human co-authors named in
# Co-Authored-By trailers. Paste the output into .github/release-notes/<tag>.md.
#
#   scripts/release_credits.sh v0.2.0            # since v0.2.0 up to HEAD
#   scripts/release_credits.sh v0.2.0 v0.3.0     # between two tags
#
# Sponsors are listed by hand from the GitHub Sponsors dashboard (respect
# anyone who chose to be private). Bots, AI co-authors and the maintainer
# are left out: the credits are for the people who helped.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
from=${1:?usage: release_credits.sh <previous-tag> [<to-ref>]}
to=${2:-HEAD}
repo=${EZCORE_REPO:-0xJ1nn/ezcore}
maintainer=${EZCORE_MAINTAINER:-0xJ1nn}
# The maintainer's account was renamed from JinUltimate1995; both are excluded.
exclude="$maintainer|JinUltimate1995"
since=$(git log -1 --format=%cI "$from")

{
  gh pr list --repo "$repo" --state merged --limit 1000 \
     --search "merged:>$since" --json author --jq '.[].author.login'
  # Human co-authors who used their GitHub noreply address.
  git log "$from..$to" --format=%B \
    | sed -nE 's/^Co-Authored-By: .*<([0-9]+\+)?([A-Za-z0-9-]+)@users\.noreply\.github\.com>.*/\2/Ip'
} | { grep -viE "^($exclude|.*\[bot\]|dependabot|github-actions|claude|copilot)$" || true; } \
  | sort -fu > /tmp/ezcore-credits.$$

echo "## Credits"
echo
if [ -s /tmp/ezcore-credits.$$ ]; then
  echo "Thank you to everyone who contributed to this release:"
  echo
  sed 's/^/- @/' /tmp/ezcore-credits.$$
else
  echo "_No outside contributions in this release yet. Yours could be the first: see CONTRIBUTING.md._"
fi
echo
echo "### Sponsors"
echo
echo "Thank you to our sponsors on [GitHub Sponsors](https://github.com/sponsors/$maintainer): <add @usernames here>."
rm -f /tmp/ezcore-credits.$$
