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

## Verdict

Clean of the literal TODO/FIXME/"not implemented" vocabulary, but not clean
of the pattern this skill actually hunts: one stale document presenting
finished-since work as missing, one real binding limitation folded into the
sentence that excuses a total feature gap, one test suite whose green hides
a dead UI action, and the single largest gap in the whole port (translation)
never written down at all until this round. None of these are exempted by
anything in `PORTING.md` — there is no `PORTING.md` in this repo to cite,
which at least means no one tried.
