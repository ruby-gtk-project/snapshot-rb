# snapshot — upstream component inventory

Upstream is GNOME Snapshot (gtk-rs, Rust + GtkBuilder `.ui`), read from
`origin/main`. The port lives on `ruby` in `lib/`.

Upstream is two crates in one tree:

- `src/` — the app: 17 widget classes, 7 `.ui` files, 1 gschema, 1 stylesheet.
- `aperture/` — a vendored camera library (GStreamer): the viewfinder widget,
  the device provider, the camera object and the QR code detector. It is not
  app code, but `ApertureViewfinder` is instantiated in `camera.ui` and is the
  single largest user-facing surface in the app, so it is inventoried here.

House mapping: one upstream source file (unioned with its `.ui`) becomes one
flat `lib/<thing>.rb`, as in the `gnome-contacts-rb` pilot. The app class stays
at `lib/snapshot/application.rb`.

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| Component files | 22 | 1 |
| Distinct GTK/Adw widget types | 41 | 5 |
| Distinct CSS classes | 24 | 0 |
| Actions | 13 | 0 |
| Accelerators | 11 | 0 |
| GSettings keys | 10 | 0 |
| Translated languages | 56 (99 msgids) | 0 |

The port is the generated stub: `lib/snapshot/application.rb` (an
`Adwaita::ApplicationWindow` + `Adwaita::ToolbarView` + `Adwaita::HeaderBar` +
`Adwaita::StatusPage` saying the port is unwritten) and `lib/snapshot.rb`.
Nothing user-facing from upstream exists yet.

---

## src/main.rs, src/application.rs → `lib/snapshot/application.rb` — the application: actions, accels, startup

| Widget | × | CSS | Signals / Actions | Notes |
|---|---:|---|---|---|
| `Gtk.Application` (upstream `Adw.Application`) | 1 | — | `activate`, `startup`, `handle-local-options` | `Adwaita::Application` is broken in the Ruby bindings; the stub already uses `Gtk::Application` |
| — | — | — | `app.quit` | the only action installed on the app |

Accelerators (`setup_accels`): `app.quit` → `<Control>q`;
`win.preferences` → `<Control>comma`; `window.close` → `<Ctrl>w`;
`win.take-picture` → `t`; `win.toggle-gallery` → `<Control>g`;
`win.toggle-guidelines` → `c`.

Startup also: `resource-base-path` `/org/gnome/Snapshot/`, default icon name,
`Adw.StyleManager.set_color_scheme(ForceDark)` — the app is always dark — and
a `--debug`/`-d` main option. `glib::set_application_name("Camera")`: the app
is called *Camera* to the user, not *Snapshot*.

Present: **yes, as a stub** — the window, toolbar view, header bar and status
page in it are placeholder, not upstream components.

## src/widgets/window.rs + data/resources/ui/window.ui → `lib/window.rb` — the main window: two navigation pages and the toast host

| Widget | × | CSS | Signals / Actions | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | `devel` (dynamic, devel builds only) | `close-request`, `notify::suspended`, `notify::is-active` | title "Camera"; size restored from `window-width`/`window-height`/`is-maximized` and saved on close |
| `Adw.ToastOverlay` | 1 | — | — | hosts every toast in the app |
| `Adw.NavigationView` | 1 | — | — | camera page is root, gallery page is pushed |
| `Adw.NavigationPage` | 2 | — | `hidden` → `on_camera_page_hidden`, `showing` → `on_camera_page_showing` | "Camera" and "Gallery"; the hidden/showing handlers stop and start the camera stream and the shutter action |
| `Camera` | 1 | — | — | → `lib/camera.rb` |
| `Gallery` | 1 | — | `item-added`, `item-removed` | → `lib/gallery.rb`; the signals enable/disable `win.toggle-gallery` and pop the gallery page when it empties |
| `Adw.Toast` | repeater | — | — | built per message in `send_toast` |

Actions installed: `win.take-picture` (async; countdown-aware), `win.about`,
`win.toggle-gallery`, `win.toggle-guidelines`, `win.preferences`, plus
`win.countdown` created from the GSettings key (stateful, `i` target).
`win.toggle-gallery` starts **disabled** and is enabled by the first gallery
item — an empty state expressed as a disabled action.

Toast strings: "Could not take picture", "Could not record video",
"Could not play camera stream", "Copied to clipboard", "Picture deleted",
"Video deleted".

Also here: the countdown timer (`countdown_start`/`cancel`/`cleanup`) and the
idle inhibitor (`inhibit`/`uninhibit`, `Gtk.ApplicationInhibitFlags::IDLE`).

Present: **no**.

## src/widgets/camera.rs + data/resources/ui/camera.ui → `lib/camera.rb` — the camera page: four states, four responsive layouts

The largest component in the app. `Adw.BreakpointBin`, CSS name `camera`.

| Widget | × | CSS | Signals / Actions | Notes |
|---|---:|---|---|---|
| `Adw.BreakpointBin` (root) | 1 | `portrait`, `mobile` (both dynamic) | `notify::current-breakpoint` | 360×294 request; `portrait` when no breakpoint or dual-portrait, `mobile` on the two dual breakpoints |
| `Adw.Breakpoint` | 3 | — | `apply` → `change_breakpoint` | `single_landscape_bp` (`max-aspect-ratio: 4/3 or max-height: 600`), `dual_portrait_bp` (`max-height: 400`), `dual_landscape_bp` (`max-aspect-ratio: 4/3 and max-width: 500`); each sets the layout name and the toggle/controls orientation |
| `Gtk.Stack` | 1 | — | — | crossfade, non-homogeneous; pages `loading`, `not-found`, `camera`, `permission-denied` |
| `Gtk.WindowHandle` | 2 | — | — | loading page, camera page |
| `Adw.ToolbarView` | 3 | — | — | loading, not-found, permission-denied |
| `Adw.HeaderBar` | 3 | — | — | one per toolbar view above |
| `Adw.Spinner` | 1 | `dimmed` | — | the `loading` state |
| `Adw.StatusPage` | 2 | — | — | **empty state** "No Camera Found" / "Connect a camera device"; **error state** "Missing Camera Permission" / "Allow camera usage in Settings"; both `camera-disabled-symbolic` |
| `Gtk.MenuButton` | 4 | `circular`, `flat` (the two in the layout view only) | `menu-model` | 2 × primary menu in the not-found and permission-denied header bars, 1 × primary menu slot, 1 × countdown button (`camera-timer-symbolic`, tooltip "Countdown") |
| `Adw.BottomSheet` | 1 | — | — | `full-width` false; opened when a QR code is detected |
| `Gtk.Overlay` | 1 | — | — | viewfinder stack under, controls over |
| `Gtk.Revealer` | 1 | — | — | crossfade; holds the recording clock |
| `Gtk.Label` | 1 | `recording-label`, `heading`, `numeric`, `osd` | — | `0∶00`, ticked once a second while recording |
| `Adw.MultiLayoutView` | 1 | — | — | four `Adw.Layout`s: `single_portrait_bp`, `dual_portrait_bp`, `single_landscape_bp`, `dual_landscape_bp` |
| `Adw.Layout` | 4 | — | — | one per breakpoint state |
| `Adw.LayoutSlot` | 14 | — | — | `countdown-button`, `primary-menu`, `camera-controls`, `camera-mode-toggle` referenced across the four layouts |
| `Adw.ToggleGroup` | 1 | `round` | `notify::active` bound bidirectionally to `capture-mode` | the mode switcher |
| `Adw.Toggle` | 3 | — | — | `picture`/`camera-photo-symbolic`/"Picture Mode", `video`/`camera-web-symbolic`/"Recording Mode", `qr-code`/`qr-code-symbolic`/"QR Code Scanning Mode" |
| `Gtk.WindowControls` | 7 | — | — | across the four layouts; one is `visible`-bound inverted to its own `empty` |
| `Gtk.CenterBox` | 7 | `cameracontrols`, `controlsframe`, `+ startcontrolsframe` (dual portrait), `+ bottom` (the two landscape bottoms) | — | the control frames |
| `Gtk.Box` | 9 | — | — | layout scaffolding |
| `Adw.Bin` | 1 | `cameracontrols`, `controlsframe` | — | wraps the start window controls |
| `Gtk.BoxLayout` | 5 | — | — | vertical window controls (layout manager, not a widget) |
| `CameraControls` | 1 | — | `camera-switched` | → `lib/camera_controls.rb` |
| `FlashBin` | 1 | — | — | → `lib/flash_bin.rb` |
| `QrScreenBin` | 1 | — | — | → `lib/qr_screen_bin.rb` |
| `GuidelinesBin` | 1 | — | — | → `lib/guidelines_bin.rb` |
| `ApertureViewfinder` | 1 | — | `notify::state`, `code-detected`, `notify::is-recording`, `picture-done`, `recording-done` | → `lib/viewfinder.rb` |
| `QrBottomSheet` | 1 | — | — | → `lib/qr_bottom_sheet.rb`; 360 width request |
| `Gtk.ShortcutController` | 1 (controller) | — | `p` → picture mode, `r` → video mode | scope Managed; built in code, not in the `.ui` |
| `Gtk.SingleSelection` | 1 (type) | — | `notify::selected-item` | model is the aperture device provider |
| `Gtk.MediaFile` | 1 (type) | — | — | plays `sounds/camera-shutter.wav` from the resource bundle |

Settings bound here: `show-composition-guidelines` → guidelines
`draw-guidelines`; `enable-audio-recording` → viewfinder
`disable-audio-recording` (inverted); `capture-mode` → own `capture-mode`;
`enable-hardware-encoding` → viewfinder `enable-hw-encoding` (get-only);
`last-camera-id` read and written on camera change.

Menus defined in `camera.ui` (no widget rows of their own, so count the items):

- `countdown_menu` — section "Countdown", 4 items, all `win.countdown` with `i` targets 0/3/5/10, labels "None", "3s", "5s", "10s".
- `primary_menu` — 1 section, 3 items: "_Preferences" `win.preferences`, "_Keyboard Shortcuts" `app.shortcuts`, "_About Camera" `win.about`.

Present: **no**.

## src/widgets/camera_controls.rs + data/resources/ui/camera_controls.ui → `lib/camera_controls.rb` — the shutter row: gallery button, shutter, camera picker

`Gtk.Box`, spacing 24, centred; margins flip with `notify::orientation`.

| Widget | × | CSS | Signals / Actions | Notes |
|---|---:|---|---|---|
| `Gtk.Stack` | 2 | — | — | `gallery_button_stack` and `camera_menu_button_stack`; both exist only so hiding a button does not move the layout |
| `Adw.Bin` | 2 | — | — | the two "fake" placeholder children |
| `GalleryButton` | 1 | — | `win.toggle-gallery` | tooltip "Open Gallery" |
| `ShutterButton` | 1 | — | `win.take-picture` | tooltip "Take Picture" (replaced per mode by the button itself) |
| `Gtk.MenuButton` | 1 | `camerabutton`, `circular` | popover built in code | `pick-camera-alt2-symbolic`, "Select Camera"; shown with 3+ cameras |
| `Gtk.Button` | 1 | `camerabutton`, `circular` | `clicked` → `on_camera_switch_button_clicked` → emits `camera-switched` | `cameras-symbolic`, "Switch Camera"; shown with exactly 2 cameras |
| `Gtk.Popover` | 1 | `menu` | — | built in `set_selection`, holds the camera list |
| `Gtk.ListView` | 1 | — | — | over the device provider `Gtk.SingleSelection` |
| `Gtk.SignalListItemFactory` | 1 (type) | — | `setup`, `bind` | makes one `CameraRow` per camera |
| `CameraRow` | repeater | — | — | one per camera, driven by the device provider |

Own signal: `camera-switched`. Own property `layout`
(`ControlsLayout::Default` / `DetectingCodes`) — in QR mode the shutter button
and the gallery stack are hidden.

Present: **no**.

## src/widgets/camera_row.rs → `lib/camera_row.rb` — one camera in the camera-picker popover

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` (root) | 1 | — | — | spacing 6 |
| `Gtk.Label` | 1 | — | — | the camera's display name |
| `Gtk.Image` | 1 | — | — | `object-select-symbolic`, visible only on the selected row |

Present: **no**.

## src/widgets/shutter_button.rs → `lib/shutter_button.rb` — the shutter: hand-drawn, five animations

`Gtk.Button` subclass with a custom `snapshot`. No child widgets.

| Facet | Detail |
|---|---|
| CSS | `shutterbutton`, `flat` added in code; stylesheet gives it 64×64 and a 999px radius |
| Properties | `shutter-mode` (`Picture`/`Video`/`Recording`), `countdown` |
| Animations | `press_ani` (4→8, 125 ms), `hover_ani` (1→1.05, 125 ms), `mode_ani` (0→1, 250 ms — lerps the fill to Red 3), `countdown_ani` (1→0, duration = countdown seconds, linear, ignores the enable-animations setting), `record_ani` (0→1, 250 ms — rotates the circle into a square) |
| Signals | `state-flags-changed` drives press and hover; tooltip changes per mode: "Take Picture" / "Start Recording" / "Stop Recording" |
| Drawing | conic-gradient countdown ring rendered to a texture (GTK issue 5755 workaround), plus a rounded-clip play/record square |

Present: **no**.

## src/widgets/gallery_button.rs → `lib/gallery_button.rb` — the thumbnail button, hand-drawn

`Gtk.Button` subclass, custom `snapshot`, no children. CSS `gallerybutton`,
`flat` added in code (44×44, 999px radius from the stylesheet). Two animations:
`size_ani` (0→1, 250 ms, played when an item is added or the last is removed)
and `hover_ani` (1→1.05, 125 ms). Draws the newest gallery item's texture over
the previous one plus a 2px border; watches the item's `loaded` property through
a `GLib.SignalGroup`.

Present: **no**.

## src/widgets/flash_bin.rs → `lib/flash_bin.rb` — the white-out flash when a picture is taken

`Adw.Bin` subclass, no children. One `Adw.TimedAnimation` (0→1, 250 ms, linear)
whose value feeds a custom easing and paints a black rect over the child.
`flash()` is called from `Camera#take_picture`.

Present: **no**.

## src/widgets/guidelines_bin.rs → `lib/guidelines_bin.rb` — rule-of-thirds composition guidelines

`Adw.Bin` subclass, no children. Property `draw-guidelines` (bound to the
GSettings key, toggled by `win.toggle-guidelines` and the `c` accel). Fades in
with a 250 ms ease-in-quad animation and draws 4 black shadow bars + 4 white
1px lines over the viewfinder's aspect-corrected rect.

Present: **no**.

## src/widgets/qr_screen_bin.rs → `lib/qr_screen_bin.rb` — the QR scanning overlay

`Adw.Bin` subclass, no children. Properties `viewfinder`, `enabled`. A 500 ms
dim animation; draws a 50%-black mask with a rounded square cut out (radius 32,
border 4) and the Pango string "Scan Code" (semibold, 16pt) under it.

Present: **no**.

## src/widgets/qr_bottom_sheet.rs + data/resources/ui/qr_bottom_sheet.ui → `lib/qr_bottom_sheet.rb` — the detected-code sheet

| Widget | × | CSS | Signals / Actions | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (root) | 1 | — | — | property `contents` |
| `Adw.PreferencesGroup` | 1 | — | — | title "Code Detected"; margins 12/12/36/36 |
| `Adw.ActionRow` | 1 | `property` | — | title "Contents", subtitle = the decoded text, markup off |
| `Gtk.Button` | 2 | `flat` | `qr-bottom-sheet.copy`, `qr-bottom-sheet.open-external` | `edit-copy-symbolic` "Copy to Clipboard" (always); `external-link-symbolic` "Open Link" shown **only** when the contents start with `http://` or `https://` |

Copy sends the "Copied to clipboard" toast; open-external uses
`Gtk.UriLauncher` and swallows `Gtk.DialogError::Dismissed`.

Present: **no**.

## src/widgets/preferences_window.rs + data/resources/ui/preferences_window.ui → `lib/preferences_window.rb` — preferences

`Adw.PreferencesDialog`, content width 360, one page "General"
(`applications-system-symbolic`).

| Widget | × | CSS | Signals / Actions | Notes |
|---|---:|---|---|---|
| `Adw.PreferencesPage` | 1 | — | — | "General" |
| `Adw.PreferencesGroup` | 3 | — | — | "General"; "Video Recording"; "Experimental" (with the graphics-driver warning description) |
| `Adw.SwitchRow` | 4 | — | `preferences-window.play-shutter-sound`, `.show-composition-guidelines`, `.enable-audio-recording`, `.enable-hardware-encoding` | "_Shutter Sound", "_Composition Guidelines", "_Record Audio", "_Hardware Video Encoding"; all `use-underline` |

Conditional: the two recording actions are **not** added while the app is
recording (`is-app-recording` construct-only property), so those rows are
insensitive; the Experimental group is visible only when hardware encoding is
supported for the chosen video format. Opened by `win.preferences`; refuses to
open if a dialog is already visible.

Present: **no**.

## data/resources/ui/shortcuts.ui → `lib/shortcuts_dialog.rb` — the keyboard shortcuts window

A standalone `Adw.ShortcutsDialog` with no backing source file; libadwaita
picks it up as `app.shortcuts` because the gresource aliases it to
`shortcuts-dialog.ui` under the app's resource base path.

| Section | Items |
|---|---|
| General | Show Shortcuts (`app.shortcuts`), Main Menu (`F10`), Open Preferences (`win.preferences`), Close Window (`window.close`), Quit (`app.quit`) |
| Camera | Picture Mode (`P`), Recording Mode (`R`), Take Picture or Start Recording (`win.take-picture`), Show/Hide Composition Guidelines (`C`) |
| Gallery | Open/Close Gallery (`win.toggle-gallery`), Next (`Right`), Previous (`Left`) |

3 × `Adw.ShortcutsSection`, 12 × `Adw.ShortcutsItem`.

Present: **no**.

## src/widgets/window.rs `show_about_dialog` + data/resources/*.metainfo.xml.in.in → `lib/about_dialog.rb` — About Camera

`Adw.AboutDialog.from_appdata` over the bundled metainfo, plus translator
credits, developers (Maximiliano Sandoval, Jamie Murphy), designers (Tobias
Bernard) and `debug_info()` — a GStreamer/Aperture/Pipewire/GTK version block
and a dump of every detected camera. Fired by `win.about`.

Present: **no**.

## src/widgets/gallery.rs + data/resources/ui/gallery.ui → `lib/gallery.rb` — the gallery page

`Adw.BreakpointBin`, CSS name `gallery` (black background from the stylesheet).

| Widget | × | CSS | Signals / Actions | Notes |
|---|---:|---|---|---|
| `Adw.BreakpointBin` (root) | 1 | — | — | 360×294, matching `camera.ui` |
| `Adw.Breakpoint` | 1 | — | — | `max-width: 500` → mobile layout, next button hexpands |
| `Adw.ToolbarView` | 1 | — | — | content extends to both edges |
| `Adw.HeaderBar` | 1 | — | — | no title; `gallery headerbar` gets a 45% black background |
| `Gtk.MenuButton` | 1 | `flat`, `circular` | menu swapped per item type | `view-more-symbolic`, "Gallery Menu" |
| `SlidingView` | 1 | — | `target-page-reached`, `notify::current-page` | → `lib/sliding_view.rb` |
| `Adw.MultiLayoutView` | 1 | — | — | layouts `desktop` and `mobile` |
| `Adw.Layout` | 2 | — | — | |
| `Adw.LayoutSlot` | 7 | — | — | `media_controls`, `prev_button`, `next_button`, `open_external` across both layouts |
| `Gtk.MediaControls` | 1 | `videoplayercontrols`, `osd` | — | visible only when the current page is a video |
| `Gtk.Button` | 3 | `osd`, `circular`, `gallerycontrols` | `gallery.next`, `gallery.previous`, `gallery.open` | "Next Image", "Previous Image", "Open in Image Viewer" — the last retitled "Open in Video Player" for videos |
| `Adw.Clamp` | 1 | — | — | max 800 px, tightening 500 px, around the media controls |
| `Gtk.Box` | 5 | — | — | layout scaffolding, 18 px margins |

Actions: `gallery.next`, `gallery.previous`, `gallery.open` (async),
`gallery.copy`, `gallery.delete` (async). Key bindings installed on the class:
`Right`/`KP_Right` → next, `Left`/`KP_Left` → previous, `Escape` →
`win.toggle-gallery`. `gallery.next`/`previous` are enabled and disabled from
the sliding view's neighbours. Own signals `item-added`, `item-removed`.

On construct it enumerates `~/Pictures/Camera` and `~/Videos/Camera`, sorts by
creation (falling back to modification) time, and prepends an item per file.

Present: **no**.

## src/utils.rs `gallery_item_menu` → `lib/utils.rb` — the per-item context menu, and the file naming

A `Gio.Menu` built in code: "_Copy Picture" or "_Copy Video" (`gallery.copy`)
then "_Delete" (`gallery.delete`), frozen. Used both as the gallery header
menu-button model and as each item's right-click popover. Also here: the
translated file names "Photo from {date}" / "Photo {number}" /
"Recording from {date}" / "Recording {number}", the `~/Pictures/Camera` and
`~/Videos/Camera` directories, and `debug_info()`.

Present: **no**.

## src/widgets/sliding_view.rs → `lib/sliding_view.rb` — the swipeable image carousel

`Gtk.Widget` subclass implementing `Adw.Swipeable`, with its own
`size_allocate`/`measure`. No child widgets of its own; its pages are
`GalleryItem`s. An `Adw.SwipeTracker` (reversed in RTL), an
`Adw.SpringAnimation` (damping 1.0, mass 0.5, stiffness 500) and a horizontal
`Gtk.EventControllerScroll` that stops propagation at the ends. Own signal
`target-page-reached`, property `current-page`. Page spacing is
`0.02 × width + 25`.

Present: **no**.

## src/widgets/gallery_item.rs → `lib/gallery_item.rb` — the base class for one gallery page

`Gtk.Widget` with a `Gtk.BinLayout`, centred. Properties `file`, `load`,
`is-picture`, `thumbnail`, `started-loading`, `loaded`, `item`. Builds a
`Gtk.PopoverMenu` (no arrow, start-aligned, end-aligned in RTL) from
`gallery_item_menu`, popped up by a `Gtk.GestureClick` on the secondary button
at the click coordinates.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.PopoverMenu` | 1 | — | — | the right-click menu |
| `Gtk.GestureClick` | 1 (controller) | — | `released` | `BUTTON_SECONDARY`, claims the sequence |

Present: **no**.

## src/widgets/gallery_picture.rs → `lib/gallery_picture.rb` — one photo page

Subclass of `GalleryItem`. Holds one `Gtk.Picture`, loads the texture through
glycin and sets the accessible label from the basename.

Present: **no**.

## src/widgets/gallery_video.rs → `lib/gallery_video.rb` — one video page

Subclass of `GalleryItem`. Holds one `VideoPlayer`, built lazily; pauses on
`unmap`; its thumbnail comes from the player.

Present: **no**.

## src/widgets/video_player.rs → `lib/video_player.rb` — the video surface

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (root) | 1 | — | — | |
| `Gtk.GraphicsOffload` | 1 | — | — | wraps the picture |
| `Gtk.Picture` | 1 | — | — | paintable is the media file; accessible label from the basename |
| `Gtk.MediaFile` | 1 (type) | — | `invalidate-contents`, `notify::playing` | realized against the window surface; playing inhibits idle |
| `Gtk.MediaControls` | 1 | `videoplayercontrols` | — | its own copy, separate from the gallery's |

Thumbnails are rendered by snapshotting the media file at 88 px and rendering
that node to a texture.

Present: **no**.

## src/enums.rs → `lib/enums.rb` — the enumerations

`PictureFormat` (`Jpeg`, translatable "JPEG"), `CaptureMode`
(`Picture`/`Video`/`QrDetection`), `ShutterMode`
(`Picture`/`Video`/`Recording`), `ControlsLayout`
(`Default`/`DetectingCodes`). The first two mirror gschema enums.

Present: **no**.

## data/org.gnome.Snapshot.gschema.xml.in → `lib/settings.rb` — the 10 settings keys

`window-width` (800), `window-height` (640), `is-maximized` (false),
`play-shutter-sound` (true), `show-composition-guidelines` (false),
`enable-audio-recording` (true), `enable-hardware-encoding` (false),
`countdown` (0), `capture-mode` (`picture`), `picture-format` (`jpeg`),
`last-camera-id` (""). Plus the two gschema enums.

Present: **no**.

## data/resources/style.css → `lib/style.rb` — the stylesheet

89 lines, 15 rules. Classes the port must both define and apply:
`shutterbutton`, `gallerybutton`, `camerabutton`, `videoplayercontrols`,
`controlsframe`, `startcontrolsframe`, `bottom`, `gallerycontrols`,
`recording-label`, `cameracontrols`, plus the element selectors `gallery`,
`camera`, `camera.portrait`, `camera:not(.mobile)`, `gallery headerbar`,
`gallery button.back`. Note `gallery button.back` is defined and never applied
by any `.ui` — dead upstream, so it is not a port gap.

Present: **no**.

## aperture/src/viewfinder.rs → `lib/viewfinder.rb` — the live camera view

1284 lines. `Gtk.Widget` subclass holding a `Gtk.Picture` over a GStreamer
`gtk4paintablesink` pipeline, with `Gtk.GraphicsOffload`. Properties `state`
(`Loading`/`Ready`/`NoCameras`/`Error`), `camera`, `detect-codes`,
`is-recording`, `aspect-ratio`, `video-format`, `disable-audio-recording`,
`enable-hw-encoding`. Signals `code-detected`, `picture-done`,
`recording-done`. Methods `start_stream`, `stop_stream`, `take_picture`,
`start_recording`, `stop_recording`.

Present: **no**.

## aperture/src/device_provider.rs, camera.rs, code_detector.rs, enums.rs, error.rs, pipeline_tee.rs, utils.rs → `lib/device_provider.rb`, `lib/camera_device.rb`, `lib/code_detector.rb` — the camera backend

`DeviceProvider` is a `Gio.ListModel` of `Camera`s with `camera-added` /
`camera-removed`; it is the model behind both the camera-picker `ListView` and
the switch/menu button logic. `Camera` carries `display-name` and the GStreamer
device. `CodeDetector` is the rqrr-based QR decoder feeding `code-detected`.
These are not widgets, but no component above works without them.

Present: **no**.

## po/ — the translation catalogue

56 languages, 99 msgids, drawn from the 7 `.ui` files, the gschema, the
metainfo, the desktop file and 6 source files (`POTFILES.in`). Several strings
carry msgctxt ("shortcut window", "Switch between front and back camera
button") or translator comments (the countdown "None"/"3s", the file-name
formats). The port has no catalogue.

Present: **no**.

---

## Blockers

1. **The viewfinder has no Ruby equivalent.** `ApertureViewfinder` is a
   GStreamer pipeline (`pipewiresrc`/`v4l2src` → tee → `gtk4paintablesink`)
   wrapped in a GTK widget. Ruby has `gstreamer` bindings, but
   `gtk4paintablesink` is a Rust plugin and the paintable has to reach GTK as a
   `Gdk.Paintable`; whether the Ruby bindings can carry that across is unproven
   and has to be tested before the camera page can show anything live. Every
   state in `camera.ui` except `not-found` and `permission-denied` depends on it.
2. **Six widgets exist only as custom `snapshot()` implementations.**
   `ShutterButton`, `GalleryButton`, `FlashBin`, `GuidelinesBin`,
   `QrScreenBin` and `SlidingView` draw themselves with `Gtk.Snapshot`,
   `graphene` and `gsk` (conic gradients, mask modes, rounded clips, rendering
   a node to a texture, Pango layouts). Subclassing a GTK widget to override
   `snapshot` from Ruby, and the availability of `Gsk.RoundedRect`,
   `Gsk.MaskMode` and `Gtk.Snapshot#push_mask` in the bindings, both need
   checking before these are planned.
3. **`SlidingView` also overrides `measure`/`size_allocate` and implements
   `Adw.Swipeable`.** Implementing a GObject interface from Ruby is a separate
   unknown from overriding virtual methods.
4. **The QR decoder.** Upstream uses the `rqrr` Rust crate. There is no
   maintained pure-Ruby QR *decoder* (`rqrcode` only encodes), so QR scanning
   mode needs either a native binding or a different approach.
5. **glycin image loading.** `GalleryPicture` loads textures through glycin's
   sandboxed loaders. The port will likely fall back to
   `Gdk::Texture.from_file`, which changes the error behaviour.
6. **The camera portal.** `Camera#start` calls `ashpd` for
   `org.freedesktop.portal.Camera` and `register_host_app`; the
   permission-denied state is driven entirely by that call's error. The port
   needs a D-Bus path to the same portal to reach that state honestly.
7. **`Adw.MultiLayoutView` / `Adw.Layout` / `Adw.LayoutSlot` / `Adw.Toggle` /
   `Adw.ToggleGroup` / `Adw.Spinner` / `Adw.BottomSheet` /
   `Adw.ShortcutsDialog` are libadwaita 1.7+ types.** Their presence in the
   installed libadwaita and their exposure through the Ruby bindings should be
   confirmed before the camera and gallery layouts are designed, since the
   responsive behaviour of both pages is built on them.
8. **No `.ui` files in the port by design**, so the four `Adw.Layout`s in
   `camera.ui` and the two in `gallery.ui` have to be rebuilt as memoized
   widget trees — the single largest mechanical chunk of the port.
