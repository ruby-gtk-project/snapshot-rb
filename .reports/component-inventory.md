# snapshot-rb — upstream component inventory

Surveyed against `origin/main` (gtk-rs/Rust, GNOME Snapshot) from the `ruby`
branch. Scope: every user-facing window, dialog, page, row, menu, shortcut,
preference, action, empty/error state, plus `.ui`, GSettings schema,
GResource manifest and `po/` catalogue.

Scan artifacts: upstream scanned at a tree snapshot of `origin/main`
(`git archive origin/main`), port scanned at `lib/`, using
`.claude/skills/component-identification/scripts/component-scan.sh` with the
GIR-built `symbols.tsv`.

## Headline

Upstream: 20 `src/widgets/*.rs` + `src/application.rs` + 7 `.blp`/`.ui`
templates/standalone objects, one GSettings schema, one GResource manifest,
78 `po/*.po` catalogues. The vendored `aperture/` crate (camera capture
pipeline: device enumeration, viewfinder, QR/barcode detection, encoding) is
a separate component surveyed on its own below because `src/widgets/camera.rs`
is built entirely on top of it.

Port (`ruby` branch, `lib/`): **every upstream unit already has a
corresponding `lib/*.rb` file.** This is not a fresh port — it is already a
structurally complete one. The gap that remains is not missing files; it is
the one upstream dependency this fleet has no Ruby binding for at all
(`aperture`), which the port substitutes with an honest "no camera found"
state rather than a live viewfinder. See Blockers.

## Component list

| Upstream file(s) | → `lib/*.rb` | Kind | Exists? |
|---|---|---|---|
| `src/main.rs` | `exe/snapshot` | entry point | yes |
| `src/application.rs` | `lib/snapshot/application.rb` | application class (actions: `app.quit`, `app.shortcuts`; accels; startup: dark scheme, stylesheet) | yes |
| `src/widgets/window.rs` + `data/resources/ui/window.ui` | `lib/window.rb` | main window (`Adw.ApplicationWindow` / toast overlay / nav view between Camera and Gallery pages; actions `win.about`, `win.preferences`, `win.take-picture`, `win.toggle-gallery`, `win.toggle-guidelines`, `countdown`) | yes |
| `src/widgets/window.rs` (`show_about_dialog`) + `data/resources/org.gnome.Snapshot.metainfo.xml.in.in` | `lib/about_dialog.rb` | about dialog (`Adw.AboutDialog`) | yes |
| `src/widgets/preferences_window.rs` + `data/resources/ui/preferences_window.ui` | `lib/preferences_window.rb` | preferences dialog (`Adw.PreferencesDialog`, 1 page / 3 groups / 4 `Adw.SwitchRow`, action-backed rows) | yes |
| `src/widgets/camera.rs` + `data/resources/ui/camera.ui` | `lib/camera.rb` | camera page (viewfinder area + flash/guidelines/QR bins, breakpoints, recording label) | yes (viewfinder itself is a stub — see Blockers) |
| `src/widgets/camera_controls.rs` + `data/resources/ui/camera_controls.ui` | `lib/camera_controls.rb` | bottom control bar (shutter button, camera-picker `Gtk.ListView`/menu, gallery button, countdown stack) | yes |
| `src/widgets/camera_row.rs` | `lib/camera_row.rb` | one row in the camera-picker popover (`Gtk.Image` + `Gtk.Label`) | yes |
| `src/widgets/shutter_button.rs` | `lib/shutter_button.rb` | the shutter `Gtk.Button` (`.shutterbutton`/`.flat`, ring animation) | yes |
| `src/widgets/flash_bin.rs` | `lib/flash_bin.rb` | flash-overlay `Adw.Bin` around the viewfinder | yes |
| `src/widgets/guidelines_bin.rs` | `lib/guidelines_bin.rb` | composition-guidelines overlay `Adw.Bin` | yes |
| `src/widgets/qr_screen_bin.rs` | `lib/qr_screen_bin.rb` | QR/barcode-detection overlay `Adw.Bin` | yes |
| `src/widgets/qr_bottom_sheet.rs` + `data/resources/ui/qr_bottom_sheet.ui` | `lib/qr_bottom_sheet.rb` | bottom sheet shown on a detected code (`Adw.ActionRow`, copy/open-external actions) | yes |
| `src/widgets/sliding_view.rs` | *(no direct file — behaviour folded into `Gallery`/`AdwNavigationView` swipe handling upstream provides natively)* | swipe-gesture container (`Gtk.EventControllerScroll`, spring animation) | **not ported as its own file** — see Blockers |
| `src/widgets/gallery.rs` + `data/resources/ui/gallery.ui` | `lib/gallery.rb` | gallery page/window (breakpoint bin, media controls, menu button, actions `gallery.copy`/`gallery.delete`/`gallery.next`/`gallery.previous`/`gallery.open`) | yes |
| `src/widgets/gallery_button.rs` | `lib/gallery_button.rb` | the floating gallery-open button (`.gallerybutton`/`.flat`, press animation) | yes |
| `src/widgets/gallery_item.rs` | `lib/gallery_item.rb` | one item's wrapper in the gallery (right-click `Gtk.PopoverMenu`, `Gtk.GestureClick`) | yes |
| `src/widgets/gallery_picture.rs` | `lib/gallery_picture.rb` | a picture slide (`Gtk.Picture`, decoded via `Gly`/`GlyGtk4`) | yes |
| `src/widgets/gallery_video.rs` | `lib/gallery_video.rb` | a video slide (`Gtk.MediaStream`) | yes |
| `src/widgets/video_player.rs` | `lib/video_player.rb` | video playback chrome (`Gtk.GraphicsOffload`/`Gtk.Picture`/`Gtk.MediaControls`, `.videoplayercontrols`) | yes |
| `data/resources/ui/shortcuts.ui` (standalone, no `.rs`) | `lib/shortcuts_dialog.rb` | keyboard-shortcuts dialog (`Adw.ShortcutsDialog`, 3 sections / 12 items) | yes |
| `src/enums.rs` | `lib/enums.rb` | shared enums (`CaptureMode`, `ShutterMode`, `ControlsLayout`, `PictureFormat`) | yes |
| `src/utils.rs` | `lib/utils.rb` | shared helpers (gallery item context menu, etc.) | yes |
| `data/org.gnome.Snapshot.gschema.xml.in` | `lib/settings.rb` | settings store — 10 keys/2 enums, backed by a JSON file instead of compiled GSettings (documented trade-off) | yes |
| `data/resources/style.css` | `lib/style.rb` | stylesheet, installed via `Gtk::CssProvider` instead of a GResource bundle | yes |
| `data/resources/resources.gresource.xml.in` | *(n/a — no GResource bundle; each resource ported individually: style inlined, metainfo constants inlined in `about_dialog.rb`, sounds not yet wired)* | resource manifest | **no GResource equivalent** — intentional, not a gap by itself, but see the sound-file item below |
| `data/resources/sounds/camera-shutter.wav` | — | shutter sound asset, played on `play-shutter-sound` | **not found under `lib/` or anywhere in the port** — no playback call exists |
| `po/*.po` (78 catalogues) + `po/POTFILES.in` | — | translation catalogue | **absent** — no `po/` directory on `ruby`; all port strings are hardcoded English literals (tracked separately — see `translation-parity` skill) |
| `aperture/` crate (`camera.rs`, `viewfinder.rs`, `device_provider.rs`, `code_detector.rs`, `pipeline_tee.rs`, `enums.rs`, `error.rs`, `utils.rs`) | — | camera-capture pipeline (device enumeration, `aperture::Viewfinder` widget, QR/barcode decode, H.264/VP8 encode) | **no Ruby binding exists for this crate at all** — `lib/camera.rb` substitutes a static "No Camera Found" status page in its place (documented in the file's header comment) |

## Blockers

- **`aperture` has no Ruby/GObject-Introspection binding.** It is a Rust
  crate vendored in this very repo (not a system library with a `.gir`), so
  none of the three mandated gems (`glycin`, `gstreamer_pbutils`,
  `libglycin-gtk4`) cover it, and there is nothing to bind against via GI.
  `lib/camera.rb` documents this honestly and shows the same "no camera"
  empty state upstream shows when `aperture::DeviceProvider` finds nothing,
  rather than faking a live feed. Live camera capture, QR/barcode detection,
  and hardware-encoded video recording are all unreachable without it. This
  is a real functional gap for full parity, not a quiet work-around of an
  available gem.
- **No `po/` catalogue.** Upstream ships 78 language catalogues; the port has
  none, so every string is English-only. Flagged for the dedicated
  `translation-parity` pass.
- **The shutter sound asset is missing.** `data/resources/sounds/camera-shutter.wav`
  has no counterpart anywhere under the port tree, and no code path plays a
  sound even though `Settings#play-shutter-sound` exists and
  `PreferencesWindow` exposes the toggle for it.
- **`src/widgets/sliding_view.rs` has no dedicated `lib/` file.** Its
  behaviour (swipe-driven paging with a spring animation) may be fully
  subsumed by `Adw.NavigationView`'s own swipe-back gesture in the port, but
  that substitution is not documented anywhere the way the `aperture`
  substitution is, so it needs a deliberate read of `gallery.rb`/`window.rb`
  to confirm there is no dropped interaction (e.g. swipe-to-advance between
  gallery items) rather than just dropped-and-forgotten code.

## Gem wiring check (per task instructions)

Verified before writing this report, no changes needed:

- `glycin` (`Gly`) — declared in gemspec, `nix/Gemfile`, required in
  `lib/gallery_picture.rb`, call path exercised (image decode).
- `libglycin-gtk4` (`GlyGtk4`, required as `require 'libglycin-gtk4'`) —
  declared, required in `lib/gallery_picture.rb`; `nix develop --command ruby
  -e "require 'libglycin-gtk4'; puts 'OK'"` succeeds in the dev shell.
- `gstreamer_pbutils` (`GstPbutils`) — declared, required in `lib/utils.rb`.
- No undeclared/unused dependency found; nothing hand-rolls a `Gio::DBusProxy`,
  shells out, or reads `/proc` in place of one of these gems.
- `gstreamer_play`/`GstPlay` correctly absent — the gemspec comment and
  `flake.nix` comment both explain upstream never needs it (video plays via
  `gtk::MediaFile`, not a GStreamer-Play binding).

No app code was written in this step, per instructions. This file is the
survey only.
