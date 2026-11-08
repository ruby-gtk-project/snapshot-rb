# Component identification — snapshot-rb vs. upstream (`origin/main`)

| | |
|---|---|
| Upstream | `main` @ `9d92e7c88f2cec448ae1e8d74207db4afa384702` |
| Port | `ruby` @ `81c790d` (HEAD at audit time) |

Upstream is Rust (gtk-rs) with GtkBuilder `.ui` templates under
`data/resources/ui/`, plus a vendored `aperture/` crate (GStreamer camera
pipeline, device enumeration, QR/code detection, caps filtering). The port
builds every widget as a memoized-accessor Ruby class with no `.ui` file
(house style), one upstream file → one `lib/<name>.rb`.

**This supersedes `.reports/component-inventory.md`.** That file is stale: it
was written after the commit `Inventory upstream components` and says
`lib/window.rb`, `lib/camera.rb` and the whole gallery are MISSING. Two
commits later (`Wire glycin/.../port the window, camera and gallery widgets`,
`Drive the app headlessly and fix three real bugs it found`) all three were
built. Leaving that file in `.reports/` as the record of the audit, uncorrected,
is itself a finding — see `accountability-ensurance.md`.

## Method

```
scripts/component-scan.sh <upstream-tree> > /tmp/up-components.tsv   # 377 rows
scripts/component-scan.sh .                > /tmp/port-components.tsv # 172 rows
```

No GIR symbol table was built (`gir-symbols.sh` needs network/package access
this sandbox doesn't have), so the scan's own type/widget/controller split was
used as printed and over-reported `type` rows (e.g. `Gtk.Accessible`,
`Gtk.Buildable`, `Adw.Easing`) were read by eye and struck per the skill's
fallback table, not counted as widgets.

## Upstream unit list (one `.rs` class, usually paired with one `.ui`)

Application shell: `src/application.rs`, `src/main.rs`, `src/config.rs.in`,
`src/enums.rs`, `src/utils.rs`, `data/org.gnome.Snapshot.gschema.xml.in`,
`data/resources/style.css`.

Window/camera/gallery widgets (20 upstream `.rs` units, 8 of them paired with
a `.ui`): `window`, `camera`, `camera_controls`, `camera_row`, `flash_bin`,
`guidelines_bin`, `qr_screen_bin`, `qr_bottom_sheet`, `shutter_button`,
`sliding_view`, `gallery`, `gallery_button`, `gallery_item`,
`gallery_picture`, `gallery_video`, `video_player`, `preferences_window`,
`shortcuts.ui` (no `.rs`, built straight from XML), plus `about_dialog`
(built inline in `window.rs`, no separate file) and the `aperture` crate
itself (`camera.rs`, `viewfinder.rs`, `device_provider.rs`, `code_detector.rs`,
`pipeline_tee.rs`, `error.rs`, `enums.rs`, `utils.rs` — camera pipeline,
not UI, so not a widget unit, but the 3 Rust unit tests upstream has both
live there, see `test-parity.md`).

## Port unit list

`lib/{application.rb is actually lib/snapshot/application.rb},
enums.rb, utils.rb, settings.rb, style.rb, window.rb, camera.rb,
camera_controls.rb, camera_row.rb, flash_bin.rb, guidelines_bin.rb,
qr_screen_bin.rb, qr_bottom_sheet.rb, shutter_button.rb, sliding_view.rb,
gallery.rb, gallery_button.rb, gallery_item.rb, gallery_picture.rb,
gallery_video.rb, video_player.rb, preferences_window.rb,
shortcuts_dialog.rb, about_dialog.rb`. 23 files, no `.ui`/`.blp` files (by
design — house style), no `aperture`-equivalent anywhere (see below).

Every upstream window/dialog/page/overlay file maps to exactly one port
file; no 1:N or N:1 splits were found. This is the one clean axis: file-level
coverage of the widget tree is complete.

## What the per-file scan actually shows (widget/css/signal/action rows)

Full counts for every mapped pair are in `/tmp/up-components.tsv` /
`/tmp/port-components.tsv` (not committed — regenerate with the commands
above). Representative, hand-checked rows that matter for parity are called
out by file in `component-parity.md`; headline ones:

- **`gallery.rs` → `lib/gallery.rb`**: upstream installs five widget-level
  actions (`gallery.next`, `gallery.previous`, `gallery.open`,
  `gallery.copy`, `gallery.delete`) via `install_action`/`install_action_async`.
  The port only wires `next`/`previous`/`open` as direct method calls from
  button `clicked` handlers; `gallery.copy` and `gallery.delete` are never
  installed as actions anywhere in the port, even though
  `Utils.gallery_item_menu` (`lib/utils.rb:111-117`) still points a
  right-click menu at those exact action names.
- **`camera.rs` + `aperture/`**: the entire live viewfinder, device
  enumeration and QR/code detection pipeline has no Ruby equivalent. The port
  always shows the "No Camera Found" status page (`lib/camera.rb:23-26`,
  the class's own header says so directly). No widget-count gap (the status
  page is itself a real upstream state, `Gtk.Stack`'s `not-found` page), but
  a total behavioural gap: a user with a real webcam gets the same screen as
  a user with none.
- **`camera.rs`' shutter-sound playback**: upstream's `play_shutter_sound`
  (`src/widgets/camera.rs:490-496`) loads
  `/org/gnome/Snapshot/sounds/camera-shutter.wav` via `Gtk::MediaFile` and
  plays it when `play-shutter-sound` is true. No `lib/*.rb` file calls
  anything sound-related; `grep -rn sound lib/` only turns up the GSettings
  key name and the Preferences switch row that edits it. The preference is
  wired to nothing.
- **`gallery_button.rs` → `lib/gallery_button.rb`**: upstream animates with
  6 `Adw::TimedAnimation`s against 2 buttons; the port's scan shows 1
  animation and 1 button. Not independently confirmed as a gap or a
  false-positive of the regex scan (upstream may double-count per-property
  animation builders) — flagged here, unresolved, rather than waved away.

## Resources not scanned here (own skills' job)

- `po/` — 56 languages, 56 `.po` files, ~102 unique `(msgctxt,msgid)` keys in
  source alone (5486 rows once every `.po` occurrence is counted). See
  `translation-parity.md` — the port has **none** of this.
- `data/resources/resources.gresource.xml.in` — icons, the shutter sound,
  `.ui` files; the port's substitute is inlined Ruby assets/CSS, not audited
  file-by-file here beyond the shutter sound above.

## Round 3 addendum (audited at `d44c0a9`)

This file's header still pins itself at `81c790d` and has not been touched
since. Four commits landed on `ruby` between `81c790d` and the current head
(`d44c0a9`) that bear directly on claims made above — most importantly
**the `gallery.copy`/`gallery.delete` gap this document still reports as
open, in the "headline" bullet list, is closed.** `db21b8b` ("Install
gallery.copy/gallery.delete GActions so the context menu works") landed
*before* `component-parity.md`'s round-2 addendum was even written, and
`lib/gallery.rb:220-232` now builds a `Gio::SimpleActionGroup` under the
`gallery` prefix with all five actions
(`next`/`previous`/`open`/`copy`/`delete`), inserted on the root widget —
confirmed by reading the file directly, not by re-running a scan. This
document's own bullet ("`gallery.copy` and `gallery.delete` are never
installed as actions anywhere in the port") is therefore **false as of
every commit after `db21b8b`**, i.e. false for the entire period this round
audits, and has been sitting uncorrected in a committed report through two
more "Parity reports" commits since. `component-parity.md`'s own round-2
addendum already states the fix is in; this file simply was never brought
back into agreement with it. This is Finding 1/Finding 6's exact shape
(a stale per-topic report, uncorrected, contradicting a sibling report on
the same question) recurring a third time — see
`accountability-ensurance.md` round 3.

Everything else checked this round against the current tree still holds:
the live-camera/aperture gap, the unwired shutter-sound preference, and the
unresolved `gallery_button.rb` animation-count discrepancy are all
unchanged by the four intervening commits (`35ec92b` dropped the unused
`gstreamer_play` gem and fixed stale comments in three files;
`de893e1`/`0012667` only touched `.reports/component-inventory.md`;
`d44c0a9` only tightened one drive-script assertion). The one substantive
code change in the whole `81c790d..HEAD` range is the `gallery.rb` action
group itself (`db21b8b`, +50/-3 lines — confirmed with
`git diff --stat 81c790d..HEAD -- lib/ exe/`); `camera.rb`,
`preferences_window.rb` and `video_player.rb` changed only in their header
comments (the `gstreamer_play` cleanup), and `lib/snapshot/rb.rb` (+8, from
`c85dfed`) is a load-path shim with no widget/CSS/signal/action content. No
other widget, CSS class, signal or action was added or removed.

**Correction, superseding the bullet above**: `gallery.rs` → `lib/gallery.rb`
installs all five of upstream's widget actions
(`gallery.next/previous/open/copy/delete`); this axis has parity.
