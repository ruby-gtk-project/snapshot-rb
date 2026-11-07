# Component inventory — snapshot-rb vs. upstream (origin/main)

Survey only; no app code written in this step. This restores and corrects the
version committed as `de893e1` ("Inventory upstream components"), which
overwrote this file (296 lines) without reading it first and, worse, got one
fact wrong in the process: it claimed `src/widgets/sliding_view.rs` had "no
dedicated `lib/` file", when `lib/sliding_view.rb` has existed all along (see
the Gallery section below). That version is still reachable at `35ec92b` for
anything not carried forward here. Everything below this point is the
restored content plus the items the `de893e1` pass additionally confirmed by
direct grep/run (now folded in rather than discarded): the shutter-sound
asset has no Ruby-side consumer at all (confirmed, not just suspected), no
`po/` directory exists on `ruby`, and the three mandated gems
(`glycin`/`libglycin-gtk4`/`gstreamer_pbutils`) are correctly required,
declared and runnable in the dev shell.

This supersedes the inventory before that one too (see
`git log -- .reports/component-inventory.md`): window, camera,
camera_controls, gallery, sliding_view, gallery_item, gallery_picture,
gallery_video, gallery_button and video_player have all landed since that
version was written, so every row that document marked `MISSING` is
re-checked here against the files that now exist.

Order follows how a user meets the app: application → window → camera page →
gallery page → dialogs → settings/support.

Upstream is Rust (gtk-rs) with GtkBuilder `.ui` templates under
`data/resources/ui/`, plus a vendored `aperture/` crate (the camera/GStreamer
device pipeline, not part of the GNOME app proper but required to build it).
The house style (see `ruby-gtk` skill, and `lib/window.rb`'s own header)
builds every widget as a memoized-accessor class with no `.ui` file, so
"present" below means a `lib/**/*.rb` class that reproduces the upstream
widget's tree, CSS classes, signals and actions — not merely a same-named
file existing.

## Summary

| | Upstream units | Present in `lib/` | Missing |
|---|---:|---:|---:|
| Widgets/dialogs/pages | 19 | 19 | 0 |

All 19 upstream widget/page/dialog units now have a corresponding `lib/`
class. The one functional gap that survives file-level completeness: there is
still no Ruby binding for `aperture` (upstream's own vendored GStreamer camera
pipeline — device enumeration, live viewfinder, QR code detection, picture/
video capture). `lib/camera.rb` says so in its own header comment and shows
the same "No Camera Found" status page the pre-camera.rb shell showed, with
`take_picture`/`start_recording` stubbed to report failure via toast. This is
not one of the four mandated gems (`glycin`, `libglycin-gtk4`,
`gstreamer_pbutils`, `gstreamer_play`) — none of those provide a camera
device provider or a live GStreamer pipeline — so it is a real, currently
unfillable gap, not a hand-rolled substitute for something a gem already
covers. Component identification stops at "does the widget/page exist and
wire up the way upstream's does"; whether the stubbed camera behaviour counts
as acceptable parity is a `component-parity` question, not this step's.

## Application shell

### `src/application.rs` + `src/main.rs` — app entry point, actions, accels
→ `lib/snapshot/application.rb` — **present**
- Kind: `Adw.Application` subclass.
- Actions: `app.quit`. Window-level actions (`win.preferences`,
  `win.about`, `win.take-picture`, `win.toggle-guidelines`,
  `win.toggle-gallery`, `win.countdown`) are installed on `Window` now that it
  exists, matching upstream's split between `Application` and `Window`.
- Accels installed by `Window#setup_accels`: `win.preferences`→
  `<Control>comma`, `win.take-picture`→`t`, `win.toggle-guidelines`→`c`.
  `win.toggle-gallery` has no accel in `Window#setup_accels` even though the
  earlier inventory recorded upstream binding `<Control>g` to it — worth
  checking against `application.rs`'s `setup_accels` directly in the
  `component-parity` pass, since this file alone doesn't show it.

### `src/config.rs.in` — build-time constants (`APP_ID`, `VERSION`, `PROFILE`, `IS_DEVEL`, `PKGDATADIR`)
→ constants inlined across `lib/snapshot/application.rb`, `lib/about_dialog.rb` — **present** (no 1:1 file; not a component)

### `src/enums.rs` — `CaptureMode`, `ShutterMode`, `PictureFormat` GEnums
→ `lib/enums.rb` — **present** (also now has `ControlsLayout`, used by
  `CameraControls`/`Camera` — check it against upstream's actual enum set in
  `component-parity`, since it isn't named in `enums.rs` by that exact list
  above).

### `src/utils.rs` — misc helpers (debug info dump, etc.)
→ `lib/utils.rb` — **present**

### `data/org.gnome.Snapshot.gschema.xml.in` — GSettings schema
→ `lib/settings.rb` — **present** (keys referenced across the port's widgets:
  `window-width`, `window-height`, `is-maximized`, `show-composition-
  guidelines`, `countdown`, `capture-mode`, `picture-format`. Not directly
  confirmed in this pass: `play-shutter-sound`, `enable-audio-recording`,
  `enable-hardware-encoding`, `last-camera-id` — grep `lib/settings.rb` for
  all eleven keys in `component-parity`.)

### `data/resources/style.css`
→ `lib/style.rb` — **present** (CSS inlined as a heredoc + `Gtk::CssProvider`).

## Window and camera page

### `src/widgets/window.rs` + `data/resources/ui/window.ui` — main window
→ `lib/window.rb` — **present** (253 lines)
- Kind: `Adw.ApplicationWindow` wrapping an `Adw.ToastOverlay` over an
  `Adw.NavigationView` with two `Adw.NavigationPage`s (`camera_page` holding
  `Camera`, `gallery_page` holding `Gallery`) — matches the template shape.
- Actions installed: `win.preferences`, `win.about`, `win.take-picture`,
  `win.toggle-guidelines`, `win.toggle-gallery`, plus the GSettings-backed
  `countdown` action via `@settings.create_action('countdown')`.
- Signals: `camera_page` `hidden`/`showing` →
  `on_camera_page_hidden`/`on_camera_page_showing`; window `close-request` →
  persist settings; `notify::is-active`/`notify::suspended` → start/stop the
  (stubbed) camera stream; `gallery` item-added/item-removed → enable/disable
  `win.toggle-gallery` and pop the nav view when empty; a `GLib::Timeout`
  drives the countdown.
- Behaviour matches the previous inventory's read of `window.rs`: window-size
  persistence, `show_about_dialog`/`show_preferences` delegate to
  `AboutDialog`/`PreferencesWindow`, countdown start/cancel, `shutter_action`
  branching on `CaptureMode`. `inhibit`/`uninhibit` for recording are present
  and call through to `@app.inhibit`/`uninhibit`.

### `src/widgets/camera.rs` + `data/resources/ui/camera.ui` — the viewfinder page
→ `lib/camera.rb` — **present** (228 lines), **functionally stubbed**
- Kind: `Adw.BreakpointBin`, CSS classes `camera`/`portrait`/`mobile`
  (breakpoint-toggled) — matches.
- Children built: `Adw.BottomSheet` (QR bottom sheet) wrapping an
  `Adw.ToolbarView` whose content is a `Gtk.Overlay` nesting `FlashBin` →
  `GuidelinesBin` → `QrScreenBin` → a `Gtk.Stack` with a "No Camera Found"
  `Adw.StatusPage`, plus a recording-duration `Gtk.Revealer`/`Gtk.Label`, and
  `CameraControls` as the toolbar's bottom bar. Three `Adw.Breakpoint`s
  (`single_landscape_bp`, `dual_portrait_bp`, `dual_landscape_bp`) toggle
  `mobile` and flip `CameraControls#orientation`, matching upstream's three.
- Gap: no `Aperture::Viewfinder` equivalent, no device picker
  `Gtk::SingleSelection`/`camera-added`/`camera-removed`, no `code-detected`
  wiring into the QR bottom sheet, no `AdwMultiLayoutView`/
  `primary_menu`. `take_picture`/`start_recording` are stubs that always
  toast failure; `start_stream`/`stop_stream`/`set_page_visible` are no-ops.
  This is the `aperture` gap described in Summary above, not a missing
  mandated gem.

### `src/widgets/camera_controls.rs` + `data/resources/ui/camera_controls.ui` — shutter row
→ `lib/camera_controls.rb` — **present** (210 lines)
- Kind: `Gtk.Box`, `halign`/`valign` center, spacing 24 — matches.
- Children: `gallery_button_stack` (`Adw.Bin` fake vs. `GalleryButton`),
  `ShutterButton`, `camera_menu_button_stack` (`Gtk.MenuButton` CSS
  `camerabutton circular` with a popover + `Gtk::ListView` camera picker, vs.
  `Gtk.Button camera_switch_button` CSS `camerabutton circular` signal
  `clicked`, vs. a fake `Adw.Bin`) — matches the three-way stack upstream
  uses for 0/1, exactly-2, and 3+ camera counts
  (`update_visible_camera_button`).
- Custom signal: `connect_camera_switched`. Listens to `gallery`
  item-added/item-removed to keep the gallery-button stack in sync, and to
  `@selection`'s `notify::selected-item` to close the popover. `set_layout`
  (named `layout=` here) hides the shutter and gallery button for
  `DETECTING_CODES`, matching upstream.

### `src/widgets/shutter_button.rs`
→ `lib/shutter_button.rb` — **present** (339 lines)

### `src/widgets/flash_bin.rs`
→ `lib/flash_bin.rb` — **present** (101 lines)

### `src/widgets/guidelines_bin.rs`
→ `lib/guidelines_bin.rb` — **present** (265 lines)

### `src/widgets/qr_screen_bin.rs` + (shares `camera.ui`'s QR surface)
→ `lib/qr_screen_bin.rb` — **present** (239 lines)

### `src/widgets/qr_bottom_sheet.rs` + `data/resources/ui/qr_bottom_sheet.ui`
→ `lib/qr_bottom_sheet.rb` — **present** (158 lines)
- Not directly re-confirmed this pass: that both of upstream's actions
  (`qr-bottom-sheet.copy` and the async open-link/share action) are both
  installed — check in `component-parity`.

### `src/widgets/camera_row.rs` — one row in the camera-picker popover
→ `lib/camera_row.rb` — **present** (68 lines); consumed by
  `CameraControls#camera_row_factory`'s `Gtk::SignalListItemFactory`.

## Gallery

### `src/widgets/gallery.rs` + `data/resources/ui/gallery.ui` — the gallery page
→ `lib/gallery.rb` — **present** (308 lines)
- Kind: wraps a `SlidingView` of `GalleryPicture`/`GalleryVideo` items read
  from `Utils.pictures_dir`/`Utils.videos_dir` with plain `Dir`/`File` calls
  (upstream uses gio's async directory enumerator; the class header
  documents the substitution as deliberate, not a hand-rolled replacement
  for a mandated gem — nothing here overlaps `glycin`/`gstreamer_*`).
- Custom signals: `connect_item_added`/`connect_item_removed`, consumed by
  `Window` and `CameraControls`. Not independently re-verified this pass:
  the `gallery.next`/`previous`/`open`/`copy`/`delete` actions and the
  `Adw.MultiLayoutView` bottom bar (media controls, prev/next, open-external)
  the earlier inventory described from `gallery.ui` — read `gallery.rb` end
  to end in `component-parity`.

### `src/widgets/sliding_view.rs` — swipeable item carousel behind the gallery
→ `lib/sliding_view.rb` — **present** (126 lines)
- Kind: wraps `Adwaita::Carousel` rather than reimplementing upstream's
  from-scratch swipe/measure/animate `Gtk.Widget` — the class header quotes
  upstream's own doc comment ("similar to AdwCarousel") as justification.
  `append`/`prepend`/`insert`/`move_to`/`remove`/`scroll_to`/`next_page`/
  `prev_page` all present; `connect_target_page_reached`/
  `connect_current_page_notify` stand in for upstream's `target-page-reached`
  signal and `notify::current-page`.

### `src/widgets/gallery_item.rs` — one item's data/model wrapper
→ `lib/gallery_item.rb` — **present** (123 lines)
- Kind: plain Ruby object (not a widget subclass — the header explains the
  Ruby bindings can't subclass this deeply and keep vfuncs/signals correct),
  base class of `GalleryPicture`/`GalleryVideo`. Owns file/is_picture/
  thumbnail/loaded state and the secondary-click `Gtk::PopoverMenu` built
  from `Utils.gallery_item_menu`.

### `src/widgets/gallery_picture.rs` — still-image gallery slide
→ `lib/gallery_picture.rb` — **present** (39 lines)
- Decodes with `Gly::Loader`/`GlyGtk4.frame_get_texture` — the mandated
  `glycin`/`libglycin-gtk4` gems, matching upstream's `glycin`/`glycin_gtk4`
  Rust calls one-for-one (sync here vs. upstream's future-based async).

### `src/widgets/gallery_video.rs` — video gallery slide
→ `lib/gallery_video.rb` — **present** (39 lines); delegates to
  `VideoPlayer` for both playback and its own thumbnail.

### `src/widgets/gallery_button.rs` — "open gallery" thumbnail button
→ `lib/gallery_button.rb` — **present** (82 lines)
- Upstream overrides `GtkWidget::snapshot()` for a GSK-node grow-in
  animation; the Ruby bindings can't override that vfunc (documented in the
  header), so this port fades the new thumbnail in with
  `Adwaita::TimedAnimation` instead — same CSS class (`gallerybutton flat`),
  same `item-added`/`item-removed` wiring, visibly different transition.

### `src/widgets/video_player.rs` — the controls/player embedded in `GtkMediaControls`
→ `lib/video_player.rb` — **present** (101 lines)
- Uses `Gtk::MediaFile` (GTK's own GStreamer-backed playback abstraction),
  matching upstream's `gtk::MediaFile` call; the header explains this is why
  the file doesn't need the `gstreamer_play` binding directly — `GstPlay` is
  one layer further down than this widget reaches, under `Gtk::MediaFile`
  itself. `thumbnail`/`snapshot_thumbnail`, `realize`, `pause` all present.

## Dialogs and support windows

### `src/widgets/preferences_window.rs` + `data/resources/ui/preferences_window.ui`
→ `lib/preferences_window.rb` — **present** (137 lines)

### `data/resources/ui/shortcuts.ui` — `AdwShortcutsDialog`, no backing `.rs`
→ `lib/shortcuts_dialog.rb` — **present** (68 lines; 3 sections / 12 items,
  matches upstream's General/Camera/Gallery breakdown per the earlier
  inventory's count).

### `Window::show_about_dialog` (inline in `window.rs`) + `data/resources/org.gnome.Snapshot.metainfo.xml.in.in`
→ `lib/about_dialog.rb` — **present** (79 lines), instantiated from
  `Window#show_about_dialog` with `version: Snapshot::Rb::VERSION`.

## Resources, schema, i18n (not components, but part of full parity)

- `data/resources/resources.gresource.xml.in` — GResource manifest; not
  applicable 1:1 (no gresource bundle by design, per `lib/style.rb`'s
  header). Every file it lists maps to something ported: the 7 `.ui` files
  above, `style.css` → `style.rb`, the metainfo → `about_dialog.rb`, 6 icon
  SVGs (asset parity, not checked here). `sounds/camera-shutter.wav` is
  **confirmed absent**: `grep -rn "wav\|shutter_sound\|camera-shutter" lib/`
  finds only the `play-shutter-sound` setting key and its preferences toggle
  (`lib/settings.rb`, `lib/preferences_window.rb`) — no file loads or plays
  the asset itself, in `ShutterButton`, `Camera`, or anywhere else. The
  setting exists but does nothing yet.
- `po/POTFILES.in` + upstream's 78 `po/*.po` catalogues — translation-parity
  is out of scope for this survey (see the `translation-parity` skill), but
  confirmed here: **no `po/` directory exists on `ruby` at all**, so every
  string in the port is an English literal.
- Icons under `data/icons/` and `data/resources/icons/` (6 SVGs under
  resources + 3 app icons) — asset parity, not checked here.
- `aperture/` — the vendored GStreamer camera-pipeline crate (device
  enumeration, viewfinder, code detection, capture). No Ruby binding exists
  for it anywhere in this ecosystem; see Summary above. This is the one
  upstream dependency that is not a GNOME-stack GI typelib and therefore
  cannot be wired in the way `glycin`/`gstreamer_pbutils`/`gstreamer_play`/
  `libglycin-gtk4` were.

## Full component list (upstream file → lib path → kind → present?)

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/application.rs`, `src/main.rs` | `lib/snapshot/application.rb` | `Adw.Application` | yes |
| `src/enums.rs` | `lib/enums.rb` | GEnums | yes |
| `src/utils.rs` | `lib/utils.rb` | helpers | yes |
| `data/org.gnome.Snapshot.gschema.xml.in` | `lib/settings.rb` | GSettings wrapper | yes |
| `data/resources/style.css` | `lib/style.rb` | CSS provider | yes |
| `src/widgets/window.rs` + `ui/window.ui` | `lib/window.rb` | `Adw.ApplicationWindow` | yes |
| `src/widgets/camera.rs` + `ui/camera.ui` | `lib/camera.rb` | `Adw.BreakpointBin` | yes (stubbed capture) |
| `src/widgets/camera_controls.rs` + `ui/camera_controls.ui` | `lib/camera_controls.rb` | `Gtk.Box` | yes |
| `src/widgets/shutter_button.rs` | `lib/shutter_button.rb` | widget | yes |
| `src/widgets/flash_bin.rs` | `lib/flash_bin.rb` | widget | yes |
| `src/widgets/guidelines_bin.rs` | `lib/guidelines_bin.rb` | widget | yes |
| `src/widgets/qr_screen_bin.rs` | `lib/qr_screen_bin.rb` | widget | yes |
| `src/widgets/qr_bottom_sheet.rs` + `ui/qr_bottom_sheet.ui` | `lib/qr_bottom_sheet.rb` | `Adw` bottom sheet | yes |
| `src/widgets/camera_row.rs` | `lib/camera_row.rb` | row widget | yes |
| `src/widgets/gallery.rs` + `ui/gallery.ui` | `lib/gallery.rb` | `Adw.BreakpointBin` | yes |
| `src/widgets/sliding_view.rs` | `lib/sliding_view.rb` | wraps `Adw.Carousel` | yes |
| `src/widgets/gallery_item.rs` | `lib/gallery_item.rb` | plain object (not `GObject`) | yes |
| `src/widgets/gallery_picture.rs` | `lib/gallery_picture.rb` | widget (glycin-backed) | yes |
| `src/widgets/gallery_video.rs` | `lib/gallery_video.rb` | widget | yes |
| `src/widgets/gallery_button.rs` | `lib/gallery_button.rb` | widget | yes |
| `src/widgets/video_player.rs` | `lib/video_player.rb` | widget (`Gtk::MediaFile`) | yes |
| `src/widgets/preferences_window.rs` + `ui/preferences_window.ui` | `lib/preferences_window.rb` | `Adw.PreferencesWindow` | yes |
| `ui/shortcuts.ui` | `lib/shortcuts_dialog.rb` | `Adw.ShortcutsDialog` | yes |
| `window.rs: show_about_dialog` + metainfo | `lib/about_dialog.rb` | `Adw.AboutDialog` | yes |
| `aperture/` crate | *(none)* | GStreamer camera pipeline | **no — no Ruby binding exists** |

## What's next (not this step)

Every file-level unit exists. What's left is:

1. **`component-parity`** on each file above, especially `window.rb`,
   `camera.rb`, `camera_controls.rb` and `gallery.rb` — the four largest and
   most-recently-landed files — to check CSS classes, signal names and
   action names match upstream exactly rather than just "a plausible
   equivalent exists."
2. **The `aperture` gap** in `camera.rb`: no live viewfinder, no capture, no
   QR detection trigger. This is a real, currently unfillable missing
   feature (no Ruby/GI binding exists for a GStreamer camera device
   provider), not something the mandated gems were supposed to cover —
   flagging it here so it isn't later described as "out of scope" or "by
   design."
3. **`test-parity`** and **`translation-parity`** — not run in this survey.
4. Items individually flagged above under each file as "not directly
   re-confirmed this pass" (accel bindings, all 11 GSettings keys, the
   QR-bottom-sheet actions, the gallery action set, shutter-sound playback) —
   each needs a direct read against upstream before being called settled.

## Mandated-gem wiring check (confirmed this pass)

Per the task's standing instructions, verified before writing this report —
no regression found, no changes made:

- `glycin` (`Gly`) — declared in the gemspec and `nix/Gemfile`, required in
  `lib/gallery_picture.rb`, and on a real call path (image decode for gallery
  stills).
- `libglycin-gtk4` (`GlyGtk4`) — declared, required in
  `lib/gallery_picture.rb` as `require 'libglycin-gtk4'`. This load path
  does resolve correctly despite the gem's typical require name being
  `libglycin_gtk4` with an underscore — confirmed live:
  `nix develop --command xvfb-run -a ruby -e "require 'libglycin-gtk4'; puts 'OK'"`
  prints `OK` in this repo's dev shell, so it is not a defect.
- `gstreamer_pbutils` (`GstPbutils`) — declared, required in `lib/utils.rb`.
- `gstreamer_play` (`GstPlay`) — correctly **absent**; the gemspec and
  `flake.nix` both explain upstream never depends on the gstreamer-play Rust
  crate or either namespace, since video playback goes through
  `gtk::MediaFile` (exposed by the `gtk4` gem itself), matching
  `lib/video_player.rb`'s own header comment.
- No undeclared/unused runtime dependency found, and nothing under `lib/`
  hand-rolls a raw `Gio::DBusProxy`, shells out, or reads `/proc` in place of
  one of these gems.
