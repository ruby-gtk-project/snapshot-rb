# Test parity — snapshot-rb vs. upstream (`origin/main`)

| | |
|---|---|
| Upstream | `main` @ `9d92e7c88f2cec448ae1e8d74207db4afa384702` |
| Port | `ruby` @ `81c790d` |
| Upstream tests | 3 |
| Ported | 0 |
| Gaps | 3 |

## Census

```sh
scripts/test-census.sh <upstream-tree> > upstream-tests.tsv
```

```
aperture/src/utils.rs	test_best_height	283
aperture/src/utils.rs	test_is_infrared	201
aperture/src/utils.rs	test_limit_fps	251
```

Three `#[test]` functions, all in `aperture/src/utils.rs`, all pure-logic
unit tests over GStreamer `Caps` filtering: `is_infrared` (whether a caps
entry describes an infrared stream, to exclude it from the device picker),
`limit_fps` (clamps/filters a caps list's frame rates), `best_height` (picks
the best resolution from a caps list for a given target). `src/` (the app
proper) has none; every upstream test lives in the vendored `aperture` crate.

Nowhere else in the upstream tree is there a `#[cfg(test)]`, `unittest`,
`pytest`, GJS `it(...)`, or GLib `Test.add_func` — confirmed by
`grep -rn '#\[test\]\|#\[cfg(test)\]' $UP/src $UP/aperture`, which returns
only these three.

## Census of the port

```sh
scripts/test-census.sh . > port-tests.tsv
```

returns 130 rows, every one of them a `d.check('...')` call inside
`test/drive_snapshot.rb` — a headless UI driver, not a test suite in the
sense the census script or upstream's own suite means. The port has:

- **`test/drive_snapshot.rb`** (476 lines, 105 `check(...)` assertions over
  30 scenarios) — a real, working, GTK-backed driver that boots the actual
  app and pokes it (verified by running it: see "Runtime gate" below).
- **`spec/`** — `spec_helper.rb` and `README.md` only. **Zero spec files.**
  `spec_helper.rb` is unmodified gem-scaffold boilerplate (it `require
  "snapshot/rb"`, a file that does not exist in `lib/` — `lib/snapshot.rb`
  and `lib/snapshot/application.rb` exist, `lib/snapshot/rb.rb` does not).
  Running `bundle exec rspec` against this would fail to even load, because
  nothing has filled the directory in since the gem was scaffolded.

## The mapping

**Zero of the 3 upstream tests have a named Ruby counterpart, in either
`test/` or `spec/`.** None of `test_best_height`, `test_is_infrared`,
`test_limit_fps` appear by name or by the behaviour they pin anywhere in the
port:

| Upstream test | Behaviour it pins | Port equivalent |
|---|---|---|
| `test_is_infrared` | A camera device whose only format is an infrared stream is excluded from the user-facing camera list | **gap** — the port has no device enumeration at all (see `component-parity.md` §3), so there is nothing to exclude from |
| `test_limit_fps` | A caps list's frame-rate range is clamped/filtered correctly before being offered to GStreamer | **gap** — same: no caps pipeline exists in the port |
| `test_best_height` | Given a caps list and a target, the resolution picker returns the expected height | **gap** — same |

All three are a direct consequence of §3 in `component-parity.md`: because
the port has no Ruby equivalent of the `aperture` camera pipeline, the three
pieces of logic upstream found worth pinning with a test have no Ruby
object to write a test against yet. That is a real reason the gap is
*hard* — it is not a reason the gap is closed, and the row stays `gap`,
not `n/a`.

## Runtime gate — reproduced, and what it actually proves

```
$ nix develop --command xvfb-run -a ruby test/drive_snapshot.rb
...
105 of 105 checks passed
DRIVE OK
```

Confirmed real: this is a genuine headless GTK run (not a dry parse), it
builds the actual window and widget tree, and all 105 checks pass. But:

- It is the **only** suite that has ever executed in this port. `spec/` has
  never run anything, because there is nothing in it to run.
- It pins UI/state behaviour the port itself invented coverage for (good,
  and worth keeping), but it pins **none** of the three properties upstream
  actually found worth a regression test. "105/105 green" and "test parity"
  are two different claims; only the second one is what this skill measures,
  and on that measure the port is 0/3.
- Two of its own checks (`test/drive_snapshot.rb:456,462`, "the file exists
  before deleting" / calling `gallery.delete` directly) call the Ruby method
  `gallery.delete`, not the `gallery.delete` GAction the real UI menu fires.
  See `component-parity.md` §1 — the suite's green does not mean the
  feature it sounds like it's testing works end to end.

## Verdict

**No test parity.** 0 of 3 upstream tests ported; both are irretrievable
until the camera-caps logic (§3 of `component-parity.md`) is built in Ruby,
at which point they become writable. The `test/drive_snapshot.rb` suite is
real, runs, and is worth keeping, but it is additional coverage the port
invented, not a port of upstream's suite — do not count it toward test
parity, and do not let "105/105" stand in for "3/3".

## Round 2 addendum (audited at `c85dfed`)

Re-ran the driver: **`107 of 107 checks passed` / `DRIVE OK`** (the `+2`
checks are the gallery.copy/gallery.delete GAction activations added when
that bug was fixed — see `component-parity.md` round-2 addendum). The
driver remains real and genuinely runs. 0 of 3 upstream `aperture` tests are
still ported, for the same reason as before: the camera/caps logic they pin
still has no Ruby object to test against (`component-parity.md` §3,
unchanged).

**A new, separate finding**: a commit on this branch
(`c85dfed`, "Fix spec runner: tolerate missing kettle-test, add
lib/snapshot/rb.rb") claims to fix the RSpec runner and cites as its proof
that `test/drive_snapshot.rb` still passes — which is true but proves
nothing about RSpec. I ran the actual command the fix is named after:

```sh
$ nix develop --command rspec
...
uninitialized constant RspecJunitFormatter (NameError)
...
No examples found.
```

`rspec` still crashes before a single example loads, because `.rspec` line 9
hardcodes `--format RspecJunitFormatter` and that gem is not present in the
dev shell's gem set — a defect the commit's own fix (a `rescue LoadError`
around `require "kettle/test/rspec"` in `spec/spec_helper.rb`) does not
touch, because the formatter is loaded by RSpec's CLI before
`spec_helper.rb` ever runs. Even past that, `spec/` still contains zero
`*_spec.rb` files (only `spec_helper.rb` and `README.md`, unchanged from the
first pass), so a working `rspec` invocation would report "No examples
found" regardless. **The spec runner is not fixed.** The commit message's
claim is broader than what it verified, and the verification line it did
include ("Verified: ... 107 of 107 checks passed / DRIVE OK") is real but is
evidence for the wrong command — this is exactly the "false green" shape
`accountability-ensurance.md` tracks; see that report's Finding 5.

Test parity remains **0/3**, now compounded by a fix commit whose own
named claim does not hold up.

## Round 3 addendum (audited at `d44c0a9`)

Upstream unchanged: still 3 `#[test]`s, all in `aperture/src/utils.rs`, none
with a Ruby counterpart — the port still has no Ruby object representing
the camera-caps pipeline these three tests pin, so the gap is unchanged and
for the same reason.

Re-ran both commands this round:

```
$ nix develop --command xvfb-run -a ruby test/drive_snapshot.rb
108 of 108 checks passed
DRIVE OK

$ nix develop --command rspec
...
uninitialized constant RspecJunitFormatter (NameError)
...
No examples found.
```

**The spec runner is still not fixed, two rounds after `c85dfed` claimed
to fix it and this ledger's round-2 addendum said so was not true.** `.rspec`
still hardcodes `--format RspecJunitFormatter` at the line this report
already named; `spec/` still holds zero `*_spec.rb` files. Four commits
landed on `ruby` since round 2 and none of them touch `.rspec` or add a
single spec file — the known, written-down defect was left exactly as
found. That is not a new failure to build; it is a known gap that nothing
in this round's four commits attempted to close, which is worth saying
plainly rather than silently re-confirming without comment: a gap flagged
in a committed report and left untouched for two more rounds is still an
open gap, not a quieter one.

The drive script's own count grew by one (`107→108`): `d44c0a9` added a
check that `GstPbutils::PLUGINS_BASE_VERSION_{MAJOR,MINOR,MICRO}` backs the
"GStreamer <version>" line in the debug-info dump with real values rather
than a placeholder. This is a genuine, narrow strengthening of an existing
check (closing a hole `test-parity.md` had not previously flagged — the old
check would have passed even if the version constants were unresolved), not
a new ported test and not movement on the 0/3 upstream-test count.

Test parity remains **0/3**. Runtime gate: **108/108**, still the only
suite that has ever executed in this port, and — per the new finding in
`component-parity.md` round 3 — still not a check on every `lib/` file
(`flash_bin.rb`, `qr_bottom_sheet.rb`, `camera_row.rb`, `video_player.rb`
have zero mentions in it). A suite that passes 108/108 while never naming
four of the port's 23 components, and while the project's only other test
framework still cannot load a single example, is a narrow runtime gate
dressed in a wide-sounding number.

## Round 4 addendum (this round)

Both of this round's named gaps are closed, checked rather than assumed:

- **The spec runner now runs.** `.rspec`'s two `RspecJunitFormatter` lines
  are gone (nothing else in `.rspec` depended on them), and
  `spec/aperture_utils_spec.rb` is a real, non-empty spec file. Verified by
  actually running it the way the dev shell's own banner says to:
  `ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format",
  "progress", "--require", "spec_helper", "spec"])'` → `7 examples, 0
  failures`. `bundle exec rspec` itself still does not work in this sandbox
  — not because of `.rspec` or missing spec files, but because the root
  `Gemfile`'s dependency closure (`kettle-test`, etc.) has never been
  `bundle install`ed here and rspec is not declared in it directly; that is
  a pre-existing, separate gap from the one this round's task named, and is
  not claimed fixed.
- **Test parity moved off 0/3.** `aperture/src/utils.rs`'s three `#[cfg(test)]`
  functions (`test_is_infrared`, `test_limit_fps`, `test_best_height`) are
  ported to `ApertureUtils` (`lib/aperture_utils.rb`) and
  `spec/aperture_utils_spec.rb`, using the `Gst-1.0` typelib loaded directly
  through `gobject-introspection` (the same mechanism `gstreamer_pbutils`'s
  own loader uses to call `gst_init_check` — there is still no packaged
  Ruby gem for core `Gst`, so this is the one legitimate way to get
  `Gst::Caps` without hand-rolling caps parsing). All three pass against
  real `Gst::Caps` objects, not mocks: **test parity 3/3** on the one slice
  of `aperture` that is pure caps arithmetic rather than a device pipeline.
  The rest of `aperture` (camera, viewfinder, device provider, code
  detector) remains untested because it remains unported — no change there.

Runtime gate grew to **130/130** (two new drive-script scenarios: a real
German-locale check per `translation-parity.md` round 4, and the
`CameraRow`/`VideoPlayer`/`FlashBin`/`QrBottomSheet` coverage below), and
spec count grew to **7/7** passing. Neither suite regressed the other.
