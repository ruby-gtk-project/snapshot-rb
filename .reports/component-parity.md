# Component parity — snapshot-rb vs. upstream (`origin/main`)

| | |
|---|---|
| Upstream | `main` @ `9d92e7c88f2cec448ae1e8d74207db4afa384702` |
| Port | `ruby` @ `81c790d` (original pass) / re-audited at `c85dfed` |

## Round 2 addendum (audited at `c85dfed`)

Re-ran the runtime gate myself: `nix develop --command xvfb-run -a ruby
test/drive_snapshot.rb` → **`107 of 107 checks passed` / `DRIVE OK`** (up
from 105; two checks were added along with the fix below). The task
description's `drive_ok=true, 107 checks passed, 0 failed, 22 components` is
confirmed real, not just quoted.

**Finding 1 (`gallery.copy`/`gallery.delete`) is genuinely fixed**, verified
by reading the code, not by trusting the commit message: `lib/gallery.rb`
now has `insert_action_group('gallery', action_group)` (line ~40) and
`action_group` (line ~227) builds a `Gio::SimpleActionGroup` installing
`next`/`previous`/`open`/`copy`/`delete`. This closes the dead-menu-item bug
on its own terms.

**Finding 2 (shutter sound) is still open**, re-verified this round:

```sh
grep -rn -i "sound\|shutter.wav\|MediaFile.*resource" lib/*.rb
```

still returns only `lib/preferences_window.rb`'s switch row and
`lib/settings.rb`'s key declaration — no playback call anywhere. Upstream
plays `camera-shutter.wav` on capture (`src/widgets/camera.rs:454-496`); the
port's shutter fire path (`lib/camera.rb`, `lib/shutter_button.rb`) has no
sound-related line. Unchanged from the first pass.

**Finding 3 (no `aperture`/camera pipeline — no live viewfinder, no device
enumeration, no QR detection, no real capture) is still total and
unchanged.** `lib/camera.rb`'s header still documents the same stub; no new
commit touches it. This remains the single largest functional gap in the
port: the user-facing core of a camera app — seeing yourself, switching
cameras, actually taking a picture from a live feed — does not exist. The
107 driven checks still never leave the "No Camera Found" branch for
anything camera-shaped; they only prove the empty/stub state, gallery
housekeeping, dialogs, settings round-trip and the stylesheet.

No new component work landed between the first pass (`81c790d`) and this
one (`c85dfed`) besides the gallery-action fix and an unrelated spec-loader
change (see `test-parity.md` round 2 and `accountability-ensurance.md`
Finding 5) — so every item left "not independently verified" below is
*still* not independently verified, and Finding 3 (camera/aperture) and
Finding 2 (shutter sound) are both still open gaps, not closed by this
round's commits.

Parity requires all four axes (count, style, behaviour, text) to hold **per
component**. Below: components checked by hand against upstream source, with
file:line evidence on both sides. Not every one of the 20 driven components
got this depth — see "Not independently verified" at the end, which the
runtime gate (105/105, 20 components) does not excuse: a component the drive
exercises only in its no-camera/empty state is unverified in its real state,
not done.

## Confirmed gaps

### 1. `gallery.copy` / `gallery.delete` GActions never installed — dead menu items

**Fixed on `ruby` after this report was written.** `lib/gallery.rb#build` now
inserts a `Gio::SimpleActionGroup` under the `"gallery"` prefix
(`#action_group`) installing `next`/`previous`/`open`/`copy`/`delete`, so
`Utils.gallery_item_menu`'s `gallery.copy`/`gallery.delete` menu items
resolve and fire for real. `test/drive_snapshot.rb` was changed to activate
`gallery.copy`/`gallery.delete` through `Gtk::Widget#activate_action` (the
same path a clicked menu item uses) instead of calling the Ruby methods
directly, closing the "green suite sitting on top of a broken feature" gap
described below. The rest of this entry is left as originally written, as
the record of what was found.

- **Upstream**: `src/widgets/gallery.rs:64-73` installs `gallery.copy` and
  `gallery.delete` as widget-level actions via `install_action` /
  `install_action_async`, alongside `gallery.next` / `gallery.previous` /
  `gallery.open` (lines 52-62).
- **Port**: `lib/gallery.rb` has `next_item`, `previous_item`, `open_with_system`
  wired directly from button `clicked` handlers (lines ~230-280), and has a
  real `copy(clipboard)` method (line ~103) and `delete` method (line ~114).
  But no `install_action`/`insert_action_group`/`Gio::SimpleActionGroup` for
  `gallery.copy` or `gallery.delete` exists anywhere in `lib/` —
  `grep -n 'install_action\|action_group' lib/*.rb` only finds action groups
  for `preferences-window` (`lib/preferences_window.rb:122`) and
  `qr-bottom-sheet` (`lib/qr_bottom_sheet.rb:99`).
- **The menu still offers both**: `Utils.gallery_item_menu` in
  `lib/utils.rb:107-120` builds a `Gio::Menu` with
  `menu.append('_Copy Picture', 'gallery.copy')` and
  `menu.append('_Delete', 'gallery.delete')`, and `Gallery#update_tooltip_and_menu`
  (`lib/gallery.rb` line ~155) sets this as `menu_button.menu_model` on every
  gallery item. GTK resolves an action name by walking up the widget's action
  group chain; since nothing in the chain installs `gallery.copy` or
  `gallery.delete`, activating either menu item is a no-op — the user sees
  "Copy Picture" and "Delete" in the right-click menu and nothing happens
  when they click them.
- **The test suite hides this.** `test/drive_snapshot.rb:336,340` only check
  that the menu *offers* the labels ("the picture context menu offers Copy
  Picture" / "...Copy Video") — string presence, never activation.
  `test/drive_snapshot.rb:456,462` call `gallery.delete` as a **direct Ruby
  method** (`gallery.delete`, `app.window.send(:gallery).delete`), bypassing
  the GAction path entirely. Every one of the 105 passing checks is
  consistent with the bug above; none of them would fail if `gallery.copy`
  stayed permanently unreachable. This is exactly the shape
  `accountability-ensurance` exists to catch: a green suite sitting on top of
  a broken feature.
- **Failure scenario**: a user long-presses/right-clicks a photo in the
  gallery and picks "Delete" from the menu — the photo is never deleted,
  with no error and no toast, because `gallery.delete` the GAction doesn't
  exist; the method of the same name is never called because nothing routes
  the click to it.

### 2. Shutter sound preference is wired to nothing

- **Upstream**: `src/widgets/camera.rs:454-455` checks
  `settings.boolean("play-shutter-sound")` and calls `self.play_shutter_sound()`,
  which (`:490-496`) plays `/org/gnome/Snapshot/sounds/camera-shutter.wav`
  via `gtk::MediaFile::for_resource`.
- **Port**: `lib/preferences_window.rb:96-97` builds a working switch row
  bound to the same `play-shutter-sound` GSettings key, and `lib/settings.rb:31`
  declares the key. But no file in `lib/` ever reads that key to play a
  sound — `grep -rn -i sound lib/*.rb` turns up only the setting's name and
  the switch row, never a `Gtk::MediaFile`, `Gst::`, or any playback call.
  `lib/camera.rb`, which owns the shutter-fire path, has no sound-related
  line at all.
- **Failure scenario**: a user takes a picture with "Shutter Sound" on in
  Preferences; upstream plays the shutter click, the port is silent, and
  nothing in `test/drive_snapshot.rb` checks for sound (it checks the
  *setting* persists — `test/drive_snapshot.rb:236` "play-shutter-sound
  starts true" — never that taking a picture plays anything).

### 3. Live camera viewfinder / device enumeration / QR code detection: total gap

- **Upstream**: the `aperture` crate (`aperture/src/{camera,viewfinder,
  device_provider,code_detector,pipeline_tee}.rs`) is a real GStreamer camera
  pipeline: it enumerates video devices, renders a live viewfinder, and emits
  `code-detected` when a QR/barcode is seen in frame (wired into
  `src/widgets/camera.rs`'s `code-detected` handler).
- **Port**: `lib/camera.rb`'s own header (lines 18-26) states plainly that no
  Ruby binding for this exists and the camera page always shows the
  "No Camera Found" status page. There is no device picker backed by a real
  device list (the `GtkListView`/`SingleSelection` machinery is built in
  `lib/camera_controls.rb` but has nothing to enumerate), and `code-detected`
  never fires because no frames are ever decoded — `QrScreenBin`/
  `QrBottomSheet` exist and are exercised by the drive script only by
  flipping `qr_screen_bin.enabled` by hand (`test/drive_snapshot.rb:171-181`),
  never by an actual detected code.
- This is the single largest gap in the port and the whole reason the drive
  script never leaves the no-camera state: nothing in the 105 checks takes a
  picture through a real camera, starts a real recording, or detects a real
  code, because none of that machinery exists to drive.
- **This is honestly disclosed in `lib/camera.rb`'s own comment** — good —
  but see `accountability-ensurance.md`: the comment states the binding
  limitation *in the same sentence* that explains the missing feature, which
  is the exact pattern the skill says turns a gap into something readers
  stop investigating.

## Discrepancy flagged, not resolved

### `gallery_button.rb` animation count

Upstream's `src/widgets/gallery_button.rs` scan shows 6
`Adw::TimedAnimation` constructions against 2 `Gtk::Button`s; the port's
`lib/gallery_button.rb` scan shows 1 animation, 1 button. This may be the
scan regex counting upstream's per-call-site animation builder pattern
multiple times for what is structurally one animation, or it may be a real
missing animation (upstream fades in on load, scales on press, and reacts to
state-flag changes separately — three concerns that could legitimately be
three `TimedAnimation`s, not one). Not read closely enough this round to
call either way — recorded as open, not waved through as "probably fine."

## Not independently verified this round (scanned, not hand-read)

`camera_controls.rb`, `camera_row.rb`, `flash_bin.rb`, `guidelines_bin.rb`,
`qr_screen_bin.rb`, `qr_bottom_sheet.rb`, `shutter_button.rb`,
`sliding_view.rb`, `gallery_item.rb`, `gallery_picture.rb`,
`gallery_video.rb`, `video_player.rb`, `preferences_window.rb`,
`shortcuts_dialog.rb`, `about_dialog.rb`, `style.rb`, `settings.rb`,
`enums.rb`, `utils.rb`, `window.rb`'s full action/accel set. The component
scan ran against all of them and found no widget-count mismatch large enough
to flag by eye, and `shortcuts_dialog.rb`'s 12 items were individually
checked against `data/resources/ui/shortcuts.ui` and match exactly (titles
and accelerators/action-names both). The rest got a scan pass, not a
line-by-line behavioural read — treat as **unverified**, not passed.

## What this means for the runtime gate

`drive_ok=true, 105/105, 20 components` was real at the first pass (reran it:
`nix develop --command xvfb-run -a ruby test/drive_snapshot.rb` → `105 of 105
checks passed / DRIVE OK`). But "20 components" the drive touches is not "20
components verified" — it never exercises gallery.copy/delete as GActions, a
real camera, a real decoded QR code, or shutter-sound playback, three of
which are confirmed broken above. A component a check only exercises in its
degraded/stub state is not a component the gate proves.

**Round 2**: now `107/107, 22 components`. gallery.copy/delete is closed (see
addendum above, and the drive script now activates both through
`Gtk::Widget#activate_action`, the real GAction path, not the Ruby method
directly). Shutter-sound playback and the entire camera/aperture pipeline
(live viewfinder, device enumeration, real capture, QR detection) are still
never exercised by any of the 107 checks — the same caveat holds at the new,
higher number: a bigger passing count from the same stub state is not more
verified, it is the same unverified surface with two more housekeeping
checks added on top.

## Round 3 addendum (audited at `d44c0a9`)

Upstream unchanged (`origin/main` still `9d92e7c8`). Four commits landed on
`ruby` since round 2's audit point: `35ec92b` (dropped the unused
`gstreamer_play` gem, fixed three stale comments), `de893e1`/`0012667`
(rewrote `.reports/component-inventory.md` twice, no `lib/`/`exe/` change),
`d44c0a9` (hardened one drive-script assertion to check
`GstPbutils::PLUGINS_BASE_VERSION_*` by exact value instead of a substring).
None touch a widget, CSS class, signal or action. Re-ran the driver:

```
$ nix develop --command xvfb-run -a ruby test/drive_snapshot.rb
108 of 108 checks passed
DRIVE OK
```

Confirmed real again — 32 scenario groups, 108 checks, one new check over
round 2 (the `GstPbutils` version-constant assertion `d44c0a9` added).

**New finding this round — which lib files the 108 checks never name at
all.** Grepping `test/drive_snapshot.rb` for every `lib/*.rb` component's
class/file name (case-insensitive) turns up **zero** mentions of
`FlashBin`, `QrBottomSheet`, `CameraRow` or `VideoPlayer` — not the class
name, not an instance check, not an action activation, nothing:

| File | Mentions in `test/drive_snapshot.rb` |
|---|---:|
| `flash_bin.rb` | 0 |
| `qr_bottom_sheet.rb` | 0 |
| `camera_row.rb` | 0 |
| `video_player.rb` | 0 |

This confirms, by direct search rather than by eye, what round 1/2's "Not
independently verified this round (scanned, not hand-read)" list already
named as unverified — but it sharpens the claim: these four are not merely
*unread by the auditor*, they are **unexercised by the only suite that
executes in this port.** `FlashBin` (the camera overlay flash animation),
`QrBottomSheet` (the bottom sheet shown in QR-detection mode),
`CameraRow` (the per-device row in the camera picker — moot today since no
device list exists, see §3, but still a built, untested widget) and
`VideoPlayer` (gallery video playback) can each be deleted, broken, or have
their `initialize` raise, and `108 of 108 checks passed / DRIVE OK` would
still print. A runtime gate that reports "108 checks … covering 20
components" without naming which 20 invites exactly this reading — the
count is real, but at least 4 of the port's 23 `lib/` files have no check
anywhere in the suite, ported or invented. Per this round's own instruction
("a component no check exercises is unverified, not done"), these four are
gaps on the behaviour axis of this skill, independent of and in addition to
the camera/aperture gap in §3.

Everything else in this file — §1 (closed), §2 (shutter sound, still open),
§3 (live camera/aperture, still open), the `gallery_button.rb` animation
discrepancy (still unresolved) — re-checked against the current tree and
unchanged.
