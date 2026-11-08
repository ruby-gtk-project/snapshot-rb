# Accountability ensurance — snapshot-rb

Scanned `lib/`, `exe/`, `.reports/` and the repo root for `PORTING.md` (it
does not exist in this port) with:

```sh
grep -rniE 'TODO|FIXME|not implemented|for now|in a future' lib/ exe/ .reports/
scripts/find-excuses.sh .
```

## What the scans found

`grep -rniE 'TODO|FIXME|not implemented|for now|in a future' lib/ exe/` —
**zero hits.** No TODO, no FIXME, no "not implemented", no "for now", no "in
a future" anywhere in the shipped code. That is a real, clean result for
those specific strings.

`scripts/find-excuses.sh .` — two hits, both in `.reports/component-inventory.md`:

```
.reports/component-inventory.md:106:no Ruby equivalent:the analogue is the BEHAVIOUR, which always has one
.reports/component-inventory.md:222:by design:borrows architectural vocabulary for an unmade decision
```

## Finding 1 — a stale, unfixed report is still presented as current

Line 106 says of `aperture`: *"no Ruby equivalent exists in this repo; this
is the single largest missing unit..."* Line 222 says of the GResource
manifest: *"the port has no gresource bundle by design — see `lib/style.rb`'s
header."* Both predate the commits that built `window.rb`, `camera.rb` and
`gallery.rb` — the whole document was written when half the app didn't exist
yet, and nothing updated it afterward. It sits in `.reports/` right now,
unflagged, next to whatever this audit adds, where the next reader has no
way to tell it is thirteen commits out of date without reading the git log
themselves, as this audit had to.

Rewritten, in the terms this skill requires:

> I wrote a component inventory, then two more commits built the camera,
> window and gallery it says are missing, and I never went back to fix the
> inventory, because I am an idiot. Upstream: `src/widgets/camera.rs`,
> `src/widgets/window.rs`, `src/widgets/gallery.rs` (all built).
> Port: `lib/camera.rb`, `lib/window.rb`, `lib/gallery.rb` (all exist, as of
> commit `8c7a0f8`) — contradicting what `.reports/component-inventory.md`
> still says today.

This is not pedantry: a stale "MISSING" in a committed report is exactly as
load-bearing, in the wrong direction, as a false "done" — a future agent who
trusts the file either re-does finished work or, worse, trusts its "present"
rows uncritically because the file otherwise looks careful and dated-sounding.
**Fix owed:** either delete `.reports/component-inventory.md` now that this
round's three reports supersede it, or add a dated correction at its top.
Leaving it as-is, silently, is the gap.

## Finding 2 — a real binding limitation stated inside the sentence that excuses the gap

`find-excuses.sh`'s keyword list didn't catch this one — it isn't "by
design" or "not applicable" in so many words — but it is the same mechanism
the skill exists to name. `lib/camera.rb:18-26`:

> "Upstream's viewfinder comes from `aperture`, a GStreamer camera pipeline
> with no Ruby binding; the four gems this port does bind against (glycin,
> libglycin-gtk4, gstreamer_pbutils, gstreamer_play) are decoders and a
> playback library, not a device provider, and do not fill that gap. So
> where upstream's viewfinder shows a live feed, this port shows the same
> 'No Camera Found' status page..."

This is calm, specific, and sounds like an architecture note — which is
exactly why it's dangerous. It states the reason ("no Ruby binding") in the
same breath as the missing feature (a live camera feed, device switching,
QR detection — the core of the app). The skill's rule is explicit: a real
binding limitation belongs in a findings doc, informing whoever picks the
work up, and **stays out of the sentence describing the gap**, because a
reader who meets a plausible obstacle in that sentence stops reading and
files the feature as settled. That is what happened here: this is a
calmly-reasoned paragraph a reviewer would nod past, sitting on top of the
single largest functional gap this audit found (see `component-parity.md`
§3) — the whole live-camera experience of the app.

Rewritten:

> I did not build a live camera viewfinder, device enumeration, or QR code
> detection — the camera page always shows "No Camera Found", on real
> hardware or none — because I am an idiot. Upstream:
> `aperture/src/{camera,viewfinder,device_provider,code_detector}.rs`, wired
> into `src/widgets/camera.rs`. Port: `lib/camera.rb` shows the `not-found`
> `Gtk::Stack` page unconditionally. (The underlying fact that this port's
> dependencies don't include a GStreamer device-provider binding is real and
> belongs in a findings note for whoever picks this up — it does not make
> the live viewfinder exist.)

## Finding 3 — a false green nobody flagged before this audit

The strongest form of this skill's warning — "a false green in a report is
the most serious finding" — applies directly to the runtime gate this round
describes as `drive_ok=true, 105 checks passed, 0 failed, covering 20
components`. That statement is true and was reproduced
(`nix develop --command xvfb-run -a ruby test/drive_snapshot.rb` →
`105 of 105 checks passed / DRIVE OK`). But two of those 105 checks
(`test/drive_snapshot.rb:456,462`) call the Ruby method `gallery.delete`
directly, while the real UI path to delete a photo is the `gallery.delete`
**GAction**, which is never installed anywhere in the port (full detail:
`component-parity.md` §1). The suite is green; the feature the green
suite's name suggests it covers — "deleting the current item" from the
actual right-click menu a user would use — does not work. Nobody wrote this
down before this audit. It is the clearest instance in this port of the
exact failure this skill exists to catch: a document (here, a terminal
"105/105 / DRIVE OK" and a task description that quotes it) read as proof
when it proves something narrower than its own headline suggests.

## Finding 4 — the biggest gap of all has no excuse language, only silence

`translation-parity.md` found 0 of 102 upstream message keys and 0 of 56
languages present in the port, with no gettext dependency, no marker, no
`po/` directory at all. There is no TODO, no "English only for now," no
excuse sentence to rewrite — the gap simply was never written down anywhere
before this audit, including in `.reports/component-inventory.md`, which
mentions `po/` only once, in passing, as "out of scope for this survey."
Silence is not better than an excuse here; it is the same failure with the
confession step skipped. The rewritten form the skill asks for still
applies even though no one wrote the original sentence:

> I shipped a port with zero of upstream's 102 translatable strings marked
> and zero of its 56 languages carried over, and no document before this
> audit said so, because I am an idiot. Upstream: `po/` (56 `.po` files,
> `po/LINGUAS`). Port: no `po/` directory exists.

## Finding 5 — a commit's own named claim does not hold up, and its "Verified:" line is evidence for the wrong command

Commit `c85dfed`, titled "Fix spec runner: tolerate missing kettle-test, add
lib/snapshot/rb.rb", ends its message with:

> "Verified: xvfb-run ruby test/drive_snapshot.rb still reports 107 of 107
> checks passed / DRIVE OK after this change."

That line is true. It is also not a verification of the thing the commit
title claims to have fixed. I ran the actual command a fixed spec runner
would need to pass:

```sh
$ nix develop --command rspec
...
uninitialized constant RspecJunitFormatter (NameError)
...
No examples found.
```

`rspec` still dies before loading a single example — `.rspec` hardcodes
`--format RspecJunitFormatter`, a gem not present in the dev shell, and
RSpec's CLI loads formatters before `spec_helper.rb` (the file this commit
touched) ever runs. Even granting that away, `spec/` holds zero `*_spec.rb`
files, so "No examples found" either way. The commit's real content — a
`rescue LoadError` around `require "kettle/test/rspec"`, and a new
`lib/snapshot/rb.rb` — is a genuine, narrow fix to one specific `LoadError`
that would occur after the formatter crash, in a hypothetical run that never
gets that far. **The commit message states a result ("Fix spec runner")
broader than anything it demonstrated, and backs it with a true sentence
about an unrelated command.** This is the false-green pattern Finding 3
found in the task's own runtime-gate description, now found again inside
this round's own work: a "Verified:" line that is accurate about what it
measured and is cited as proof of something else. Full detail:
`test-parity.md` round-2 addendum.

Rewritten:

> I titled a commit "Fix spec runner" and did not fix the spec runner —
> `rspec` still crashes on a missing formatter gem before it reads a single
> file — because I am an idiot who verified the wrong command and wrote
> down the result as if it answered the question in my own commit title.
> Upstream: n/a (Ruby-side tooling, no upstream equivalent).
> Port: `.rspec:9` still names `RspecJunitFormatter`, which is not in the
> nix devshell's gem set; `spec/` still has zero `*_spec.rb` files.

## Finding 6 — three overlapping, mutually-contradicting documents in `.reports/` for the same question

`.reports/` currently holds three documents answering "what components
exist": `component-identification.md` (written against `81c790d`, opens by
declaring itself the authority and `component-inventory.md` stale/superseded),
`component-inventory.md` (written *later*, against a newer HEAD, and itself
declares the *previous* `component-inventory.md` superseded — but never
mentions `component-identification.md` exists at all), and this round's
`component-parity.md` addendum. A reader who opens `component-identification.md`
first is told `component-inventory.md` is stale and wrong; a reader who opens
`component-inventory.md` first is told nothing about
`component-identification.md` and has no way to know a second, contradicting
"authoritative" document exists. Both cannot be the live authority
simultaneously, and nothing in either says which one a reader should trust
today. This is Finding 1's exact failure (a stale document presented as
current) recurring one level up: not within one file this time, but across
a growing pile of same-topic files that each claim supersession without
checking what else is in the directory.

Rewritten:

> I wrote a second component inventory without reading the first one I'd
> already written to find out it also claimed to be the final word, and now
> there are two documents in `.reports/` that each say "trust me, not the
> other one," except only one of them knows the other exists — because I am
> an idiot who treated "write a new report" as a substitute for "check what
> the directory already says." Upstream: n/a. Port:
> `.reports/component-identification.md` and
> `.reports/component-inventory.md`, both still present, uncorrected,
> contradicting each other about which is current.
>
> **Fix owed, not yet made**: either delete one in favour of the other, or
> add one line at the top of each naming which document in `.reports/` is
> the one to trust as of the latest commit. This round's `component-parity.md`
> is the one to treat as current for parity questions; this file and
> `test-parity.md`/`translation-parity.md` are current for their own
> questions. No file does this bookkeeping yet.

## Verdict

Clean of the literal TODO/FIXME/"not implemented" vocabulary in `lib/` and
`exe/` (re-confirmed this round — same scan, same zero hits), but not clean
of the pattern this skill actually hunts: one stale document presenting
finished-since work as missing, one real binding limitation folded into the
sentence that excuses a total feature gap, one test suite whose green hides
a dead UI action (now fixed — see Finding 3's update in
`component-parity.md`), the single largest gap in the whole port
(translation) never written down at all until the first audit round, a
"Fix spec runner" commit this round whose own verification line answers a
different question than its title asks, and three overlapping reports in
`.reports/` that each claim to be the current word on components without
checking each other. None of these are exempted by anything in
`PORTING.md` — there is no `PORTING.md` in this repo to cite, which at
least means no one tried.

## Round 3 (audited at `d44c0a9`)

Re-ran the literal scan — `grep -rniE 'TODO|FIXME|not implemented|for now|in
a future' lib/ exe/ .reports/` and `scripts/find-excuses.sh .` — against the
four commits that landed since round 2 (`35ec92b`, `de893e1`, `0012667`,
`d44c0a9`). Still zero TODO/FIXME/"not implemented" hits in `lib/`/`exe/`.
No new excuse-shaped sentence was introduced by any of the four; their
commit messages (read in full, not just titles) are plainly worded and each
names what it did and did not fix — `d44c0a9` in particular explicitly
lists what it leaves open (shutter sound, `po/`, the aperture pipeline)
*without* folding the reason into the sentence that describes the gap, the
exact discipline Finding 2 asked for. That is a genuine improvement in this
round's own commits, worth recording as such rather than only hunting for
new failures.

### Finding 6, recurring a third time — and worse

Round 1 flagged two same-topic documents in `.reports/`
(`component-identification.md`, `component-inventory.md`) that each
claimed supersession without checking the other existed. Nothing was fixed
between rounds 1 and 3: `de893e1` and `0012667` both rewrote
*only* `component-inventory.md` again — `0012667`'s own message says so
("The previous commit on this path overwrote a more detailed inventory
without reading it first") — and **neither commit's message, nor the
resulting file, mentions `component-identification.md` exists.** The
specific contradiction Finding 6 warned about was theoretical in round 1
(both files happened to agree at the time); this round it became real and
checked out: `component-identification.md` (still pinned at `81c790d`)
states as a live finding that `gallery.copy`/`gallery.delete` are "never
installed as actions anywhere in the port," which has been false since
`db21b8b`, a commit that landed *before* `component-identification.md` was
even written — meaning the document was wrong about the port's state on
the day it was committed, not only today. `component-parity.md`'s own
round-2 addendum, written later, correctly says this gap is closed. Two
committed reports in the same `.reports/` directory now give opposite
answers to "does `gallery.delete` work," and the fix (this round's
`component-identification.md` round-3 addendum, written as part of this
same audit) is the first thing in three rounds to say so.

Rewritten:

> I was told, in round 1, that leaving two contradicting same-topic reports
> in `.reports/` with no cross-reference was itself a finding, and in the
> next two rounds I rewrote one of them twice and never once opened the
> other to check whether it still agreed — so a committed report sat for
> three rounds asserting a bug was present that had already been fixed
> before the report was written, because I am an idiot who treats "write a
> new report" as a substitute for "read what's already in the directory,"
> every single time, even after being told. Upstream: n/a. Port:
> `.reports/component-identification.md` (claims the gap is open, pinned at
> `81c790d`) vs. `.reports/component-parity.md` (claims it closed, as of
> `c85dfed`) vs. the actual file, `lib/gallery.rb:220-232` (closed, since
> `db21b8b`, which predates both reports).

### Finding 7 — a known, named gap left untouched across a full round for no stated reason

`test-parity.md`'s round-2 addendum named a specific defect
(`.rspec`'s hardcoded `RspecJunitFormatter`, zero files in `spec/`) and
said plainly the spec runner was not fixed despite a commit title claiming
otherwise. Four commits landed on `ruby` since then. None touches `.rspec`
or adds a spec file — confirmed with `git diff c85dfed..HEAD -- .rspec
spec/`, which is empty. That is not itself a violation — nothing requires
every round to close every gap — but it is also not written down anywhere
until this round's `test-parity.md` addendum says so explicitly. A
previously-identified, specific, two-line fix sitting untouched across a
full round of otherwise-active work (four commits, one of them adding a
new drive-script check) is worth naming as "known and left," rather than
letting a reader assume silence means it was addressed.

### Verdict, round 3

Still clean of the literal TODO/FIXME vocabulary, and this round's own four
commits are honestly worded. But the pattern this skill exists to catch
recurred, in a sharper form than before: a stale report
(`component-identification.md`) that was already wrong about the port's
state on the day it was committed, sitting uncorrected through two further
"Parity reports" commits, next to a sibling report that had the right
answer the whole time. Finding 6 is not a one-off from round 1 — it is a
standing failure mode of keeping one per-topic report per skill in the same
directory without ever diffing them against each other, and three rounds
of this audit have now caught it, named a fix, and watched the next round
not apply it. The fix applied in this round's own
`component-identification.md` addendum is the first correction; whether it
sticks is for round 4 to check, not assume.
