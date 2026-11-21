# DCO attestation

**Date: 22 November 2026.** This page records a fact about this repository's
history, the statement that covers it, and the command that shows the statement
has held since. The certificate itself is [`DCO`](../DCO) at the repository
root; the contribution rules are in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## The finding

The repository asks for a `Signed-off-by:` trailer on every commit, in
`CONTRIBUTING.md` and in [`LICENSING.md`](LICENSING.md). The history does not
show that for its whole length. When this was measured, the main branch held
259 commits: 66 carried a trailer and 193 did not. One signed commit landed
while this page was being written, so the head attested below holds 260
commits and still the same 193 without a trailer:

    $ git log --format='%H %(trailers:key=Signed-off-by,valueonly,separator=%x2c)' \
        16a6100fef20f24e0992cab49b6819ea65f4f90d \
        | awk 'NF==1{u++} NF>=1{t++} END{print u" of "t" commits carry no sign-off"}'
    193 of 260 commits carry no sign-off

Of those 193, 141 are ordinary commits and 52 are merges: 28 created by the
hosting platform in a pull request, 24 made locally by the maintainer. A merge
adds no content of its own, since every commit it brings in is already in the
range. The first commit with a trailer is from 19 September 2026; the earliest
commits, from 11 September 2026, have none.

The 193 are not evidence that other people's work went unattributed. Every
commit reachable from the main branch has the same author:

    $ git log --format='%ae' origin/main | sort -u
    92670540+0xJ1nn@users.noreply.github.com

One address, `0xJ1nn`. Its display name appears as `0xJ1nn` and, after the
account was renamed, as `Formerly JinUltimate`. The `Signed-off-by:` trailers
in the history carry five identities, all of them the maintainer's:

| Trailer identity | What it is |
| --- | --- |
| `0xJ1nn <92670540+0xJ1nn@users.noreply.github.com>` | current account |
| `JinUltimate1995 <JinUltimate1995@users.noreply.github.com>` | earlier account name |
| `0xJ1nn <jinultimate1995@gmail.com>` | earlier mailbox |
| `JinUltimate <jinultimate@JinUltimates-MacBook-Air.local>` | the maintainer's laptop |
| `The ezCORE maintainers <maintainers@ezcore.dev>` | project address, from November 2026 |

Setting aside the automated assistants named in `Co-Authored-By:` and
`Assisted-by:` trailers, no address of any other person appears in the history,
on any branch. Coverage for the first four identities rests on the maintainer's
word, which is why the fifth exists: from 22 November 2026 the project address
gives future commits a name that does not depend on a personal mailbox. So the
rights chain was never broken. What was incomplete is the record of it: the
project claimed a sign-off it had not, in fact, been collecting.

## The remedy, and the one that was rejected

Two remedies are legitimate. The first is to state the position for the history
as it stands, in a tracked file, signed by the person who holds the rights. The
second is to rewrite each unsigned commit to add the trailer.

This repository took the first. The second was rejected because rewriting a
commit changes its hash and the hash of every commit after it: the release tags
`v0.1.0`, `v0.1.1` and `v0.2.0` would point at commits that no longer exist,
every open pull request would need rebuilding, and every outside reference to a
commit would break. It would also write a certification into commit messages in
a form the author never wrote when the work was done, which is the opposite of
what a certificate is for. A dated statement covers the same ground, can be
checked, and leaves the history as it happened. It is the ordinary way a project
formalises the DCO after the fact.

## What the statement covers

The maintainer certifies the Developer Certificate of Origin 1.1 for the whole
history in this inclusive range:

| | |
| --- | --- |
| Oldest commit covered | `0da3826568faff2075f303c6b207808d27bf5de0` (11 September 2026) |
| Newest commit covered | `16a6100fef20f24e0992cab49b6819ea65f4f90d` (22 November 2026) |
| Attested on | 22 November 2026 |
| Author of every commit in range | `0xJ1nn <92670540+0xJ1nn@users.noreply.github.com>` |

The commit that adds this page is signed, so it needs no retroactive coverage.
It sits outside the range above, and the range names the history as it stood
when the statement was made. That commit is also where the certificate is
signed: it carries a `Signed-off-by:` trailer under the project address, and
`git log -1 -- docs/DCO-ATTESTATION.md` names it.

From this date forward the rule is the ordinary one. Every ordinary commit
carries a `Signed-off-by:` trailer, written with `git commit -s`, and the
maintainer signs under one of the two addresses in `DCO` §1. A merge commit adds
no content of its own and carries none. An `Assisted-by:` trailer discloses
automated help; it is not a signature, claims no authorship, and adds no rights
holder.

## Confirm it yourself

One line, from a clone of this repository, checks every ordinary commit added
since the attested head and fails if any of them lacks a sign-off:

    git fetch -q origin && git log --no-merges --format='%H %(trailers:key=Signed-off-by,valueonly,separator=%x2c)' 16a6100fef20f24e0992cab49b6819ea65f4f90d..origin/main | awk 'NF==1{print "UNSIGNED " $1; u++} NF>=1{t++} END{print t+0 " commit(s) since the attestation, " u+0 " without a sign-off"; exit (u>0)}'

It prints `0 commit(s) since the attestation, 0 without a sign-off` today and
exits 0. `--no-merges` is there on purpose: merges are not expected to carry a
trailer, so counting them would report a failure that is not one. Drop it, and
put the attested commit in place of the range, to count the whole branch.

## What this does and does not establish

This is an evidentiary fix, and it should be read as one. It records, in a dated
and checkable form, that a single person authored the history and certifies the
certificate for it. It does not change who holds copyright, and it does not turn
the history into something it was not. The underlying rights were never in
question, because there is one author and that author is the maintainer.

Three things it cannot supply. It cannot prove that the older trailer
identities belong to the maintainer, beyond the maintainer's statement: the
account-linked address is the only one a stranger can tie to a GitHub account by
looking. It cannot bind a third party, because it is the licensor's own
statement rather than someone else's grant. And it is not a signed Contributor
License Agreement: where a distributor, a store or a court needs an instrument
rather than a certification, the document to ask for is the CLA, whose current
text is still a draft and has not been reviewed by a lawyer.

What this page adds is the part that can be shown from the repository alone: who
wrote the history, when the certification was made, and that the rule has held
since.
