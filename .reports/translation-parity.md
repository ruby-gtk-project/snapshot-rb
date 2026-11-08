# Translation parity — snapshot-rb vs. upstream (`origin/main`)

| | |
|---|---|
| Upstream | `main` @ `9d92e7c88f2cec448ae1e8d74207db4afa384702` |
| Port | `ruby` @ `81c790d` |
| Upstream catalogue keys | 102 (source-extracted `(msgctxt, msgid)` pairs) |
| Upstream languages | 56 (`po/LINGUAS`, 56 `po/*.po` files) |
| Port catalogue keys | **0** |
| Port languages | **0** |
| Gaps | 102 keys + 56 languages |

## Census

```sh
scripts/msgid-census.sh <upstream-tree> > upstream-msgids.tsv   # 5486 rows (includes every .po occurrence)
scripts/msgid-census.sh .                > port-msgids.tsv      # 0 rows
cut -f1,2 upstream-msgids.tsv | sort -u | wc -l   # 102 unique (msgctxt, msgid) keys
cut -f1,2 port-msgids.tsv      | sort -u | wc -l   # 0
```

56 `.po` files under `<upstream>/po/`, matching `po/LINGUAS` (56 lines).
Upstream's source alone (not counting `.po` re-occurrences) extracts to 102
distinct keys, pulled from `_()`/`gettext()` call sites in `src/`,
`<template translatable="yes">` attributes in the `.ui` files, and
`.desktop.in`/metainfo strings.

## The port's catalogue: zero

```sh
grep -rEn "(^|[^a-zA-Z0-9_])_\(['\"]" lib/ exe/   # no matches
grep -n gettext Gemfile snapshot-rb.gemspec        # no matches
find . -iname po -o -iname '*.po' -o -iname LINGUAS  # no matches
```

- **No gettext marker of any kind** (`_`, `N_`, `C_`, `NC_`, `ngettext`,
  `n_`, `s_`, `pgettext`, or the Ruby `gettext` gem's equivalents) appears
  anywhere in `lib/` or `exe/`. An earlier grep for `_(` during this audit
  matched `enum_(`/`capture_mode =` calls, not translation markers — once
  those false positives are excluded, the true count is 0.
- **No `gettext` dependency** in `Gemfile` or `snapshot-rb.gemspec`.
- **No `po/` directory, no `.po` file, no `LINGUAS` file, no `.pot`**
  anywhere in the port tree.
- Every user-visible string in the port — every button label, tooltip,
  dialog title, toast message, menu item, preferences row title — is a bare
  Ruby string literal: `'Previous Image'`, `'_Copy Picture'`,
  `'Could not take picture'`, etc. None of it is marked, so none of it is
  extractable, and even if it were byte-identical to upstream's English it
  would not connect to upstream's `.po` files, because nothing in the port
  calls `gettext` to do the lookup.

## Why this is total, not partial

Translation parity needs three things to hold, and all three are absent:

1. **Key sets equal** — upstream 102, port 0. Not close.
2. **Byte-identical msgids** — vacuously true of an empty set and
   meaningless: there is nothing to compare.
3. **Languages ship** — upstream's 56 `.po` files do not exist in the port
   at all, so even if every string were later marked and happened to match
   upstream's English byte-for-byte, none of the 56 donated translations
   would be reachable without separately importing the `.po` files and
   wiring a `.mo` build into the port (`rake`/`meson`), neither of which
   exists.

`translator_credits = 'translator-credits'` is set correctly in
`lib/about_dialog.rb:73` (the standard GNOME convention string gettext
replaces with real names once translated) — but with no `.po` files to
translate it, this will simply display the literal string
"translator-credits" forever, which is the About dialog visibly broken for
every non-English-reading tester, not a polish item.

## Verdict

**Zero translation parity.** The 56 languages upstream ships are entirely
unreachable from this port as it stands — not "English only for now" (not a
state this skill recognizes) but 102 missing keys and 56 missing catalogues,
full stop. This is the largest single gap found in this audit by any
measure (component count, test count, or translated-string count) and it
received no mention at all in `.reports/component-inventory.md` beyond a
one-line "out of scope for this survey" flag — see
`accountability-ensurance.md`.

## Round 2 addendum (audited at `c85dfed`)

Re-ran the census commands from this report against the current tree
(`lib/`, `exe/`, `Gemfile`, `snapshot-rb.gemspec`): still no gettext marker,
no `gettext` dependency, no `po/` directory, no `.po`/`LINGUAS`/`.pot` file
anywhere. The two commits that landed since the first pass
(`db21b8b` gallery actions, `c85dfed` spec-loader fix) touch no
user-visible string and no catalogue infrastructure. **Unchanged: 0 of 102
keys, 0 of 56 languages.** This remains the single largest gap in the port
and the runtime gate (now 107/107) does not exercise translation at all —
the driver never switches locale, so a 107/107 green run and 0/102
translation keys coexist without contradiction, which is exactly why this
ledger has to be read on its own and not inferred from the drive script's
pass count.

## Round 3 addendum (audited at `d44c0a9`)

Re-ran every census command from the top of this report against the
current tree. Upstream unchanged (`origin/main` @ `9d92e7c8`, still 102
keys / 56 languages). Port side, re-confirmed from scratch rather than
assumed carried-forward:

```sh
grep -rEn "(^|[^a-zA-Z0-9_])_\(['\"]" lib/ exe/     # no matches
grep -n gettext Gemfile snapshot-rb.gemspec          # no matches
find . -iname po -o -iname '*.po' -o -iname LINGUAS  # no matches
```

Still zero on every count. The four commits since round 2
(`35ec92b`, `de893e1`, `0012667`, `d44c0a9`) touch gem dependencies, two
`.reports/` documents and one drive-script assertion — none add a user-
visible string, a gettext call, or catalogue infrastructure of any kind.
**Unchanged: 0 of 102 keys, 0 of 56 languages.** This remains the single
largest gap in the port, now spanning three audit rounds with no commit
anywhere on `ruby` attempting to close any part of it (no `gettext`
dependency added, no marker introduced, no `po/` directory created). The
runtime gate grew to 108/108 in the same period without exercising
translation at all, for the same reason round 2 already gave: the driver
never switches locale and has no mechanism that could.

## Round 4 addendum (this round, audited at `f4cdd9e` before this round's commits)

This round actually wires it, rather than adding a fourth round of "still
zero" commentary. What changed, verified by rerunning the skill's own
commands rather than by reading the code and assuming:

- **`gettext` is a real runtime dependency now**, not just loadable in the
  dev shell. `snapshot-rb.gemspec` adds `spec.add_dependency("gettext", "~>
  3.4")`, `nix/Gemfile` adds `gem "gettext"`, and `nix/gemset.nix` was
  regenerated with `bundix -l` after deleting the old lock — the devshell
  already carried `pkgs.rubyPackages_3_4.gettext` for the `rxgettext`
  extractor, which is a separate, unrelated package and does **not** put
  gettext in the packaged app's own closure. Proven, not assumed: `nix build
  .#default`, then invoking `gems.wrappedRuby`'s own `ruby -rbundler/setup`
  directly (env stripped of the dev shell's extra `GEM_PATH` entries)
  resolves `require "gettext"` to gettext 3.5.2 from the bundlerEnv, not
  3.5.1 from the dev shell's separate package.
- **`po/` is upstream's, unchanged.** `cp` from a worktree of `origin/main`
  @ `9d92e7c8` — all 56 `.po` files and `LINGUAS`, byte for byte, nothing
  hand-edited, nothing regenerated. `diff <(ls po/*.po | xargs -n1 basename
  -s .po | sort) <(sort po/LINGUAS)` is empty — LINGUAS matches the file
  list exactly, same as upstream.
- **`lib/i18n.rb`** binds the `snapshot` domain (upstream's
  `meson.project_name()`, confirmed from `meson.build:43`, not
  `snapshot-rb`) against `locale/` at the repo root, and documents the one
  real trap hit while wiring it: `GetText#bindtextdomain` binds per
  *including* class, so a module with `def self.x` methods (`Utils`) needs
  `Snapshot::I18n.bind(self)` (an `extend`), not `include`, or `_()` silently
  returns the untranslated string with no error at all.
- **A second, sharper trap, found by actually building the `.mo`s and then
  checking the compiled output rather than trusting that the task ran**:
  `GetText::Tools::Task`, the mechanism this skill's own `ruby-gettext.md`
  reference recommends, assumes the gem's own nested `po/<lang>/<domain>.po`
  layout. Pointed at upstream's flat GNOME layout (`po/<lang>.po`), its
  `po:update` step ran `rmsginit`/`rmsgmerge` and wrote a **brand new**
  `po/de/snapshot.po` merged from current source with no prior translations
  to merge against, then compiled *that* — a `.mo` with every key present
  and every value empty. The first attempt looked like success (56 `.mo`
  files written, no errors) and was not: `GetText::MO#load_from_file(...)
  ["Camera"]` on the result came back `nil`. Caught before committing only
  because this ledger's own Step 5 requires loading a compiled `.mo` and
  reading a real key out of it, not just running the task and counting
  files. Fixed by hand: the `Rakefile`'s `gettext:mo` task calls
  `GetText::Tools::MsgFmt.run` directly, once per `po/<lang>.po`, and never
  writes into `po/` at all. Reported as a defect against this skill's own
  reference doc — the recipe there needs either a layout caveat or a working
  example against a flat `po/*.po` tree.
- **Strings actually marked**, this round, in `lib/`: `camera.rb`,
  `camera_controls.rb`, `shutter_button.rb`, `preferences_window.rb`,
  `qr_screen_bin.rb`, `qr_bottom_sheet.rb`, `gallery.rb`, `utils.rb`,
  `window.rb`, `about_dialog.rb`, `shortcuts_dialog.rb`. Every msgid
  transcribed from upstream's own source (`git -C <upstream-worktree> show
  9d92e7c8:...`), byte for byte — including one upstream inconsistency kept
  deliberately: `shortcuts.ui`'s "Open Preferences" carries the context
  `"Shortcut window description"` while every sibling item carries
  `"shortcut window"`, almost certainly a typo in *upstream*, preserved
  exactly rather than tidied, because the msgctxt is part of the catalogue
  key translators were actually sent.
- **Two real gaps closed as components, not just as strings**:
  `Gallery#copy`/`#delete` never sent a toast at all — `"Copied to
  clipboard"`, `"Picture deleted"`, `"Video deleted"` were upstream msgids
  with nowhere in the port for them to live. `Gallery` now takes an
  `on_toast:` callback (`Window` wires it to `#send_toast`, the same pattern
  `Camera` already used), and the drive script's own
  `gallery.copy`/`gallery.delete` steps now assert on toast text too — this
  was a reachable, testable gap, not a stub.
- **One reword fixed while marking it**: `camera.rb`'s status-page
  description said *"Connect a camera to take pictures and videos"*;
  upstream's is *"Connect a camera device"*. Byte-identical now.
- **Rerunning this report's own census command** (`msgid-census.sh .`,
  filtered to `lib/`/`exe/`, deduped on `(ctxt, msgid)`) finds **38** marked
  messages the scanner can read directly (it cannot follow `shortcuts_dialog.rb`'s
  `SECTIONS` table — the title strings reach `p_()` through a variable, the
  same "unresolved marker" shape this skill's own `gnome-tour` worked
  example describes for its `PAGES` table). Hand-censusing that table the
  way the skill prescribes for exactly this shape adds its 15 titles (3
  section names + 12 items, all under `msgctxt "shortcut window"` except the
  one noted above) for **53 of upstream's 102 keys ported**, verified
  against upstream's own `po/de.po` by loading the compiled `.mo` and
  reading real German back out — not inferred from `_()` appearing in the
  diff. `49 gaps` remain, named below rather than left implicit.
- **The required last check, run rather than assumed**: `test/drive_snapshot.rb`
  now sets `GetText.locale = 'de'`, fires `win.take-picture` and asserts
  the toast comes back `"Bild konnte nicht aufgenommen werden"` (not
  `"Could not take picture"`), and separately asserts a shutter-mode
  tooltip comes back `"Aufnahme starten"`. Both pass (`130 of 130 checks
  passed`, `DRIVE OK`), and both values were read out of `po/de.po` itself,
  not retyped from memory. German reaches the screen; this is not a
  catalogue that merely parses.

### What is still a gap (49 of 102)

- **Everything from `data/org.gnome.Snapshot.gschema.xml.in`** (11 keys —
  `Capture mode`, `Countdown timer`, `Enable audio recording`, and friends)
  and **everything from `data/resources/org.gnome.Snapshot.metainfo.xml.in.in`**
  beyond the four already ported through `about_dialog.rb`'s constants, and
  **everything from `data/org.gnome.Snapshot.desktop.in.in`** (`Camera`,
  `Take pictures and videos`, the `picture;photos;camera;...` keywords) —
  this port has no `.desktop`, no gschema XML and no metainfo file at all
  (component-parity gap, not a translation-only one; the `Port site` cell
  for all ~17 of these is "no such file in this port").
- **`JPEG`** (`enums.rb`'s `PictureFormat::DISPLAY_NAMES`) is marked-ready
  (`N_`) but genuinely unreachable: nothing in this port calls
  `.display_name` on a `PictureFormat` member — there is no picture-format
  preference row to show it in (`preferences_window.rb` only exposes the
  four switch rows upstream's gschema-backed rows cover; a picture-format
  chooser was never built). Left untranslated-at-use rather than wired to a
  UI element that does not exist.
- **`Open Gallery`** (`camera_controls.ui`'s gallery-button tooltip) — the
  port's `GalleryButton` has no tooltip at all; adding translated text to a
  tooltip upstream has and this port's button does not would be adding a
  component, not porting one.
- The rest: `An ID representing the last used camera`, `Default window
  height/width/maximized behaviour`, `Last Camera Used ID`, `Picture format`,
  `Whether to ...` (the five settings-description strings), `Enable debug
  messages` (a CLI flag `src/application.rs` has and this port's `exe/`
  entry point does not take any flags at all), and the handful of `.ui`
  strings for features this port has not built (`Missing Camera Permission`,
  `Allow camera usage in Settings`, the permission-request page `camera.ui`
  shows that this port's camera page has no equivalent state for).

None of these 49 are rewordings or extra port-only strings — `summary.extra`
is 0. Every one is a key this port has not reached yet, named here rather
than silently absent. The next round's honest options are: build the
`.desktop`/gschema/metainfo files this port has never had (closes ~17 at
once, and is a `component-identification.md` question first), or keep
closing one-off `lib/` strings as their owning component gets built.

### Toolchain checks not run

`msgfmt -c` (GNU gettext's own `.po` validator) was not run against the 56
imported files — only `rmsgfmt` (the gem's own, which produced working
`.mo`s, read back and verified above). `rake gettext:mo` was exercised by
invoking the Rake task directly in this session, not through a committed CI
job; nothing in `test/drive_snapshot.rb` rebuilds `locale/` itself, so a
`.mo` going stale relative to `po/` would not be caught by the drive script
— only by rerunning `rake gettext:mo` by hand. `locale/` is `.gitignore`d
build output and is not committed; a fresh checkout needs `rake gettext:mo`
run once before any non-English locale will actually show translated text
(the gem is wired either way, so `_()` never raises — it just falls back to
the English msgid until the `.mo`s exist on disk).
