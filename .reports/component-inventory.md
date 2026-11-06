# Component inventory — snapshot-rb vs. upstream (origin/main)

Survey only; no app code written in this step. Order follows how a user
meets the app: application → window → camera page → gallery page → dialogs
→ settings/support.

Upstream is Rust (gtk-rs) with GtkBuilder `.ui` templates under
`data/resources/ui/`. The house style (see `ruby-gtk` skill, and
`lib/snapshot/application.rb`'s own header) builds every widget as a
memoized-accessor class with no `.ui` file, so "exists" below means a
`lib/**/*.rb` class that reproduces the upstream widget's tree, CSS classes,
signals and actions — not merely a same-named file.

## Summary

| | Upstream units | Present in `lib/` | Missing |
|---|---:|---:|---:|
| Widgets/dialogs/pages | 19 | 9 | 10 |

The missing ten are the camera pipeline and the gallery — the two biggest and
most behaviourally dense parts of the app. Everything currently in `lib/` is
the shell around them (dialogs, settings, overlays, utilities) plus three
camera-page overlay widgets (flash, guidelines, QR) that don't themselves
need the video pipeline.

## Application shell

### `src/application.rs` + `src/main.rs` — app entry point, actions, accels
→ `lib/snapshot/application.rb` — **present**
- Kind: `Adw.Application` subclass.
- Actions: `app.quit`. (Upstream's window-level actions are installed on
  `Window`, not `Application`.)
- Accels: `app.quit`→`<Control>q`, `win.preferences`→`<Control>comma`,
  `window.close`→`<Ctrl>w`, `win.take-picture`→`t`,
  `win.toggle-gallery`→`<Control>g`, `win.toggle-guidelines`→`c`. The port's
  `ACCELS` constant also carries `app.shortcuts`→`<Control>question`, which
  does not appear in upstream's `setup_accels` (upstream shows shortcuts via
  the default `<Control>question`/F1 Adwaita gives `Adw.Application`
  automatically) — worth checking the port isn't double-binding.
- Notes: sets `Adw::ColorScheme::ForceDark`, sets app-id, installs the
  stylesheet. The class doc explicitly says it only builds "the shell
  upstream's window and camera page share" and that camera/gallery pages are
  not yet wired in — this matches the gap below.

### `src/config.rs.in` — build-time constants (`APP_ID`, `VERSION`, `PROFILE`, `IS_DEVEL`, `PKGDATADIR`)
→ constants inlined across `lib/snapshot/application.rb`, `lib/about_dialog.rb` — **present** (no 1:1 file; not a component)

### `src/enums.rs` — `CaptureMode`, `ShutterMode`, `PictureFormat` GEnums
→ `lib/enums.rb` — **present**

### `src/utils.rs` — misc helpers (debug info dump, etc.)
→ `lib/utils.rb` — **present**

### `data/org.gnome.Snapshot.gschema.xml.in` — GSettings schema
→ `lib/settings.rb` — **present** (keys: `window-width`, `window-height`,
  `is-maximized`, `play-shutter-sound`, `show-composition-guidelines`,
  `enable-audio-recording`, `enable-hardware-encoding`, `countdown`,
  `capture-mode`, `picture-format`, `last-camera-id`). Verify `lib/settings.rb`
  covers all eleven keys, not just the window-geometry ones.

### `data/resources/style.css`
→ `lib/style.rb` — **present** (CSS inlined as a heredoc + `Gtk::CssProvider`,
  per the file's own header comment).

## Window and camera page

### `src/widgets/window.rs` + `data/resources/ui/window.ui` — main window
→ **`lib/window.rb` — MISSING**
- Kind: `Adw.ApplicationWindow` template (`AdwToastOverlay` →
  `AdwNavigationView` with two `AdwNavigationPage`s: `camera_page` holding
  `Camera`, `gallery_page` holding `Gallery`).
- Actions installed: `win.take-picture` (async), `win.about`,
  `win.toggle-gallery`, `win.toggle-guidelines`, `win.preferences`, plus a
  GSettings-backed `countdown` action (`settings.create_action`).
- Signals: `camera_page`'s `hidden`/`showing` → `on_camera_page_hidden` /
  `on_camera_page_showing` (start/stop the camera stream and shutter
  enablement); `gallery.connect_item_added`/`item_removed` toggle
  `win.toggle-gallery`'s enabled state and pop the nav view when the gallery
  empties; `notify::is-active` kicks off `camera.start()` once; `notify::
  suspended` stops/restarts the stream; countdown timer drives the shutter.
- Behaviour: window-size persistence to GSettings, devel CSS class,
  `show_about_dialog` (→ `AboutDialog`, present), `show_preferences_window`
  (→ `PreferencesWindow`, present), countdown start/cancel/cleanup,
  `shutter_action` (branches on `CaptureMode`).
- This is the hub that would wire together every widget below; none of it
  exists yet.

### `src/widgets/camera.rs` + `data/resources/ui/camera.ui` — the viewfinder page
→ **`lib/camera.rb` — MISSING**
- Kind: `Adw.BreakpointBin` template, CSS class `portrait` (toggled by
  current breakpoint, also `mobile`).
- Template children (13): a `GtkStack` with `loading` / `not-found` /
  `content` pages, an `Aperture::Viewfinder`, `CameraControls`,
  `FlashBin`, `GuidelinesBin`, `QrScreenBin`, a camera `GtkSingleSelection`
  (for the device picker), `AdwBreakpoint`s (`single_landscape_bp`,
  `dual_portrait_bp`, `dual_landscape_bp`), `AdwMultiLayoutView` and a
  `GtkMenuButton` with `primary_menu`.
  - Breakpoints swap `AdwMultiLayoutView` layout name and flip
    `camera_mode_toggles`/`camera_controls` orientation; each has an `apply`
    signal → `change_breakpoint`.
- Signals it connects to: device provider `camera-added`/`camera-removed`;
  viewfinder `notify::state`, `code-detected` (QR), `notify::is-recording`,
  `picture-done`; selection `notify::selected-item`; `camera_controls`'
  `camera-switched`; `notify::current-breakpoint`.
- Depends on `aperture` crate (the camera/GStreamer pipeline, code detection,
  device enumeration) — no Ruby equivalent exists in this repo; this is the
  single largest missing unit and the one most likely to need the mandatory
  binding gems (`gstreamer_play`/`gstreamer_pbutils`, and `glycin`/
  `libglycin-gtk4` for thumbnail/image decode once captures land in the
  gallery).

### `src/widgets/camera_controls.rs` + `data/resources/ui/camera_controls.ui` — shutter row
→ **`lib/camera_controls.rb` — MISSING**
- Kind: `GtkBox` template (`halign`/`valign` center, spacing 24).
- Children: `GtkStack` `gallery_button_stack` (`AdwBin` fake vs. real
  `GalleryButton`, action `win.toggle-gallery`), `ShutterButton`
  (action `win.take-picture`), `GtkStack` `camera_menu_button_stack`
  (`GtkMenuButton camera_menu_button` CSS `camerabutton circular` with a
  `GListModel` camera-picker popover built in code and CSS class `menu`, vs.
  `GtkButton camera_switch_button` CSS `camerabutton circular`, signal
  `clicked`→`on_camera_switch_button_clicked`, vs. a fake `AdwBin` page).
- Custom signal: `camera-switched`. Connects to `gallery.item-added`/
  `item-removed` to keep the gallery-button stack in sync.

### `src/widgets/shutter_button.rs`
→ `lib/shutter_button.rb` — **present**

### `src/widgets/flash_bin.rs`
→ `lib/flash_bin.rb` — **present**

### `src/widgets/guidelines_bin.rs`
→ `lib/guidelines_bin.rb` — **present**

### `src/widgets/qr_screen_bin.rs` + (shares `camera.ui`'s QR surface)
→ `lib/qr_screen_bin.rb` — **present**

### `src/widgets/qr_bottom_sheet.rs` + `data/resources/ui/qr_bottom_sheet.ui`
→ `lib/qr_bottom_sheet.rb` — **present**
- Actions on upstream: `qr-bottom-sheet.copy` and one async action (open
  link/share) — worth confirming the port installs both.

### `src/widgets/camera_row.rs` — one row in the camera-picker popover
→ `lib/camera_row.rb` — **present**

## Gallery

### `src/widgets/gallery.rs` + `data/resources/ui/gallery.ui` — the gallery page
→ **`lib/gallery.rb` — MISSING**
- Kind: `Adw.BreakpointBin` template, same `360×294` size floor as `Camera`
  (comment: "must match the requests in camera.ui").
- Breakpoint: `max-width: 500` → `multi_layout` layout `mobile`,
  `next_button.hexpand = true`.
- Children: `AdwToolbarView` with `AdwHeaderBar` (title hidden, end
  `GtkMenuButton menu_button` CSS `flat circular`, tooltip "Gallery Menu"),
  content `SlidingView`, bottom `AdwMultiLayoutView multi_layout` with four
  named slots: `media_controls` (`GtkMediaControls`, CSS `videoplayercontrols
  osd`), `next_button`/`prev_button` (`GtkButton`, action `gallery.next`/
  `gallery.previous`, CSS `osd circular gallerycontrols`), `open_external`
  (action `gallery.open`, CSS `osd gallerycontrols circular`); two
  `AdwLayout`s (`desktop`, `mobile`) arrange those slots differently.
- Actions installed: `gallery.next`, `gallery.previous`, `gallery.open`
  (async), `gallery.copy`, `gallery.delete` (async).
- Custom signals: `item-added`, `item-removed` (consumed by `Window` and
  `CameraControls` above). Internally listens to `sliding_view`'s
  `target-page-reached` and `notify::current-page`.

### `src/widgets/sliding_view.rs` — swipeable item carousel behind the gallery
→ **`lib/sliding_view.rb` — MISSING**
- Kind: custom `Gtk.Widget` (not template-backed; built entirely in code).
- Controllers: `Adw::SwipeTracker` (`begin-swipe`/`update-swipe`/
  `end-swipe`), `Gtk::EventControllerScroll` (`scroll`) — both behaviour-only,
  not widgets, but essential to port (drag/scroll paging between gallery
  items).
- Custom signal: `target-page-reached`; animates with `Adw::TimedAnimation`
  (`connect_done`).

### `src/widgets/gallery_item.rs` — one item's data/model wrapper
→ **`lib/gallery_item.rb` — MISSING**
- Kind: plain `GObject` (not a widget) wrapping a captured file; has a
  `Gtk::GestureClick`-style `released` connection point used by callers.

### `src/widgets/gallery_picture.rs` — still-image gallery slide
→ **`lib/gallery_picture.rb` — MISSING**
- Kind: widget wrapping `Gtk.Picture`/`Gtk.MediaFile`-style loading, with a
  construct-only `load` property (lazy decode). A natural candidate for the
  `glycin`/`libglycin-gtk4` gems once this is ported — do not hand-roll image
  decoding here.

### `src/widgets/gallery_video.rs` — video gallery slide
→ **`lib/gallery_video.rb` — MISSING**
- Kind: widget wrapping video playback for a captured clip.

### `src/widgets/gallery_button.rs` — "open gallery" thumbnail button
→ **`lib/gallery_button.rb` — MISSING**
- Kind: `Gtk.Widget`/button subclass, CSS classes `gallerybutton flat`.
  Bindings via `connect_notify_local`; listens to `gallery.item-added`/
  `item-removed` to show the latest thumbnail.

### `src/widgets/video_player.rs` — the controls/player embedded in `GtkMediaControls`
→ **`lib/video_player.rb` — MISSING**
- Kind: wraps a `Gtk.MediaFile` stream; CSS class `videoplayercontrols` on
  its `controls` child. Signals: `notify::invalidate-contents`,
  `notify::playing`. This is squarely GStreamer-playback territory —
  `gstreamer_play` (`GstPlay`) is the mandatory gem for this, not a
  hand-rolled player.

## Dialogs and support windows

### `src/widgets/preferences_window.rs` + `data/resources/ui/preferences_window.ui`
→ `lib/preferences_window.rb` — **present**

### `data/resources/ui/shortcuts.ui` — `AdwShortcutsDialog`, no backing `.rs`
→ `lib/shortcuts_dialog.rb` — **present** (3 sections / 12 items, matches
  upstream's General/Camera/Gallery breakdown).

### `Window::show_about_dialog` (inline in `window.rs`) + `data/resources/org.gnome.Snapshot.metainfo.xml.in.in`
→ `lib/about_dialog.rb` — **present**

## Resources, schema, i18n (not components, but part of full parity)

- `data/resources/resources.gresource.xml.in` — GResource manifest; not
  applicable 1:1 (the port has no gresource bundle by design — see
  `lib/style.rb`'s header), but every resource it lists (icons, sounds,
  `.ui` files, metainfo, style.css) should have a corresponding Ruby-side
  equivalent or asset. `data/resources/sounds/camera-shutter.wav` in
  particular has no obvious Ruby-side consumer yet — grep `lib/` for shutter
  sound playback once `Camera`/`ShutterButton` land.
- `po/POTFILES.in` + 65 `po/*.po` catalogues — translation-parity is out of
  scope for this survey (see the `translation-parity` skill); flagged only so
  the next step doesn't assume English-only strings are correct.
- Icons under `data/icons/` and `data/resources/icons/` (6 SVGs) — asset
  parity, not widget parity; not checked here.

## Full component list (upstream file → lib path → kind → present?)

| Upstream file(s) | → `lib/` path | Kind | Present |
|---|---|---|---|
| `src/application.rs`, `src/main.rs` | `lib/snapshot/application.rb` | `Adw.Application` | yes |
| `src/enums.rs` | `lib/enums.rb` | GEnums | yes |
| `src/utils.rs` | `lib/utils.rb` | helpers | yes |
| `data/org.gnome.Snapshot.gschema.xml.in` | `lib/settings.rb` | GSettings wrapper | yes |
| `data/resources/style.css` | `lib/style.rb` | CSS provider | yes |
| `src/widgets/window.rs` + `ui/window.ui` | `lib/window.rb` | `Adw.ApplicationWindow` | **no** |
| `src/widgets/camera.rs` + `ui/camera.ui` | `lib/camera.rb` | `Adw.BreakpointBin` | **no** |
| `src/widgets/camera_controls.rs` + `ui/camera_controls.ui` | `lib/camera_controls.rb` | `Gtk.Box` | **no** |
| `src/widgets/shutter_button.rs` | `lib/shutter_button.rb` | widget | yes |
| `src/widgets/flash_bin.rs` | `lib/flash_bin.rb` | widget | yes |
| `src/widgets/guidelines_bin.rs` | `lib/guidelines_bin.rb` | widget | yes |
| `src/widgets/qr_screen_bin.rs` | `lib/qr_screen_bin.rb` | widget | yes |
| `src/widgets/qr_bottom_sheet.rs` + `ui/qr_bottom_sheet.ui` | `lib/qr_bottom_sheet.rb` | `Adw` bottom sheet | yes |
| `src/widgets/camera_row.rs` | `lib/camera_row.rb` | row widget | yes |
| `src/widgets/gallery.rs` + `ui/gallery.ui` | `lib/gallery.rb` | `Adw.BreakpointBin` | **no** |
| `src/widgets/sliding_view.rs` | `lib/sliding_view.rb` | custom `Gtk.Widget` | **no** |
| `src/widgets/gallery_item.rs` | `lib/gallery_item.rb` | `GObject` model | **no** |
| `src/widgets/gallery_picture.rs` | `lib/gallery_picture.rb` | widget | **no** |
| `src/widgets/gallery_video.rs` | `lib/gallery_video.rb` | widget | **no** |
| `src/widgets/gallery_button.rs` | `lib/gallery_button.rb` | widget | **no** |
| `src/widgets/video_player.rs` | `lib/video_player.rb` | widget | **no** |
| `src/widgets/preferences_window.rs` + `ui/preferences_window.ui` | `lib/preferences_window.rb` | `Adw.PreferencesWindow` | yes |
| `ui/shortcuts.ui` | `lib/shortcuts_dialog.rb` | `Adw.ShortcutsDialog` | yes |
| `window.rs: show_about_dialog` + metainfo | `lib/about_dialog.rb` | `Adw.AboutDialog` | yes |

## What's next (not this step)

The ten missing units are exactly the camera/GStreamer pipeline and the
gallery/video-playback surface — the parts most likely to need the mandatory
binding gems (`glycin`, `gstreamer_pbutils`, `gstreamer_play`,
`libglycin-gtk4`) rather than hand-rolled equivalents. Any future port of
`Camera`, `GalleryPicture`, `GalleryVideo` or `VideoPlayer` should wire those
gems in before writing widget code, per the fork's standing instructions.
