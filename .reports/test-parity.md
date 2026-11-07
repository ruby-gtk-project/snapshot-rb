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
