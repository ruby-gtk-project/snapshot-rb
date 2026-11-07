# Component parity — snapshot-rb vs. upstream (`origin/main`)

| | |
|---|---|
| Upstream | `main` @ `9d92e7c88f2cec448ae1e8d74207db4afa384702` |
| Port | `ruby` @ `81c790d` |

Parity requires all four axes (count, style, behaviour, text) to hold **per
component**. Below: components checked by hand against upstream source, with
file:line evidence on both sides. Not every one of the 20 driven components
got this depth — see "Not independently verified" at the end, which the
runtime gate (105/105, 20 components) does not excuse: a component the drive
exercises only in its no-camera/empty state is unverified in its real state,
not done.

## Confirmed gaps

### 1. `gallery.copy` / `gallery.delete` GActions never installed — dead menu items

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

`drive_ok=true, 105/105, 20 components` is real (reran it:
`nix develop --command xvfb-run -a ruby test/drive_snapshot.rb` → `105 of 105
checks passed / DRIVE OK`). But "20 components" the drive touches is not "20
components verified" — it never exercises gallery.copy/delete as GActions, a
real camera, a real decoded QR code, or shutter-sound playback, three of
which are confirmed broken above. A component a check only exercises in its
degraded/stub state is not a component the gate proves.
