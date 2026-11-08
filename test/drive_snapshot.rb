# frozen_string_literal: true

# Drives the whole app headlessly: builds the window, exercises the camera
# page's no-camera state, the shutter/countdown/video-record paths, guideline
# and QR-detection toggles, the preferences/about/shortcuts dialogs, the
# gallery with real decoded pictures and a broken video file, window
# accelerators, and the stylesheet. Screenshots each state.
#
# Why this file exists: a GTK app that loads is not a GTK app that works.
# `ruby -c` passes on code that builds an empty window, and the Ruby bindings
# differ from the C API in ways that only a run reveals — the first run of
# this script found that Window#show_about_dialog referenced the bare
# constant `Rb::VERSION` from a top-level class, which NameErrors because
# `Rb` is nested inside `Snapshot`, not a top-level constant. No about dialog
# had ever actually been opened by anyone before this script ran it.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_snapshot.rb
#
# This machine's GTK4 has no offscreen backend — gtk_init fails outright with
# no display — so xvfb-run is not optional here.
#
# The specs under spec/ cover the display-free half. What is driven here is
# what needs a widget: the wiring, the state swaps and anything a screenshot
# can show.

require 'fileutils'
require 'tmpdir'
require 'cairo'

$stdout.sync = true

# Scratch XDG directories, so a run never reads or writes the real user's
# settings, pictures or videos.
ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('snapshot-drive-config')
PICTURES_DIR = Dir.mktmpdir('snapshot-drive-pictures')
VIDEOS_DIR = Dir.mktmpdir('snapshot-drive-videos')
ENV['XDG_PICTURES_DIR'] = PICTURES_DIR
ENV['XDG_VIDEOS_DIR'] = VIDEOS_DIR

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'snapshot'
require_relative 'gtk_driver'

SHOTS = File.expand_path('../tmp/shots', __dir__)
FileUtils.rm_rf(SHOTS)

# Turns the main loop over for `ms` milliseconds and comes back. A step
# cannot sleep: every step runs inside a GLib timeout, so the clock a sleep
# would wait on is dispatched by the very loop the sleep would block.
def pump(ms)
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) + (ms / 1000.0)).then do |deadline|
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      GLib::MainContext.default.iteration(false)
    end
  end
end

# Writes a small, genuinely decodable PNG at `path` — glycin sniffs content,
# not the extension, so this is a real picture file regardless of what it is
# named, the same way a real capture would be.
def write_test_picture(path, color: [1.0, 0.0, 0.0])
  Cairo::ImageSurface.new(:argb32, 24, 24).then do |surface|
    Cairo::Context.new(surface).tap do |ctx|
      ctx.set_source_rgb(*color)
      ctx.paint
    end
    surface.write_to_png(path)
  end
end

GtkDriver.drive(Snapshot::Application.new, shots: SHOTS) do |d, app|
  d.window { app.window.window }

  # Collects every toast Window#send_toast is asked to show, without
  # changing the port: the window instance already dispatches through this
  # one method, so overriding it on this one instance (after `build` has
  # run, before anything triggers a toast) observes every toast sent from
  # here on without touching lib/.
  toasts = []

  d.step('the window builds and shows the camera page with no camera') do
    app.window.define_singleton_method(:send_toast) { |text| toasts << text }

    d.check('the window is an Adwaita::ApplicationWindow') do
      app.window.window.is_a?(Adwaita::ApplicationWindow)
    end
    d.check('it is the only toplevel') { Gtk::Window.list_toplevels.length == 1 }
    d.check('its title is Camera') { app.window.window.title == 'Camera' }
    d.check('the camera page is showing') do
      app.window.send(:navigation_view).visible_page.equal?(app.window.send(:camera_page))
    end
    d.check('the status page says no camera was found') do
      app.window.send(:camera).send(:status_page).title == 'No Camera Found'
    end
    d.check('the gallery button stack shows the empty placeholder') do
      app.window.send(:camera).send(:camera_controls).send(:gallery_button_stack)
         .visible_child_name == 'fake-gallery-button'
    end
    d.check('the shutter button starts in picture mode') do
      app.window.send(:camera).send(:camera_controls).send(:shutter_button).shutter_mode ==
        Enums::ShutterMode::PICTURE
    end
    d.check('shutter is enabled (the camera page is showing)') do
      app.window.window.lookup_action('take-picture').enabled?
    end
    d.shot('01-camera')
  end

  d.step('the composition-guidelines toggle flips the camera overlay and the setting') do
    guidelines = app.window.send(:camera).send(:guidelines_bin)

    d.check('guidelines start off') { !guidelines.draw_guidelines }
    app.window.window.lookup_action('toggle-guidelines').activate(nil)
    d.check('the action turned them on') { guidelines.draw_guidelines }
    d.check('and wrote it to settings') { app.settings.show_composition_guidelines? }

    app.window.window.lookup_action('toggle-guidelines').activate(nil)
    d.check('activating again turns them back off') { !guidelines.draw_guidelines }
    d.check('and the setting followed') { !app.settings.show_composition_guidelines? }
  end

  d.step('the flash overlay plays and reports its own animation state') do
    flash_bin = app.window.send(:camera).send(:flash_bin)

    d.check('it is not flashing before being told to') { !flash_bin.flashing? }
    flash_bin.flash
    d.check('flash started the animation') { flash_bin.flashing? }
    pump(300)
    d.check('the animation finished on its own') { !flash_bin.flashing? }
  end

  d.step('the QR bottom sheet fills in its row and reacts to URL content') do
    sheet = app.window.send(:camera).send(:qr_bottom_sheet)

    sheet.contents = 'just some text'
    d.check('the subtitle took the plain text') { sheet.send(:action_row).subtitle == 'just some text' }
    d.check('the open-link button is hidden for non-URL contents') { !sheet.send(:open_external_button).visible? }
    d.check('url? is false for plain text') { !sheet.url? }

    sheet.contents = 'https://example.com/code'
    d.check('the subtitle took the URL') { sheet.send(:action_row).subtitle == 'https://example.com/code' }
    d.check('the open-link button appears for URL contents') { sheet.send(:open_external_button).visible? }
    d.check('url? is true for an https URL') { sheet.url? }

    copied = []
    sheet.send(:bin).clipboard.define_singleton_method(:set) { |text| copied << text }
    sheet.send(:bin).activate_action('qr-bottom-sheet.copy', nil)
    d.check('the copy GAction is reachable and copies the current contents') do
      copied == ['https://example.com/code']
    end
  end

  d.step('taking a picture with no camera refuses with upstream\'s toast') do
    toasts.clear
    app.window.window.lookup_action('take-picture').activate(nil)
    d.check('the toast is the no-camera one') { toasts == ['Could not take picture'] }
    d.check('no recording is active') { !app.window.send(:camera).is_recording_active? }
  end

  d.step('German actually reaches the screen, not just the catalogue (translation-parity skill, step 5)') do
    original_locale = GetText.locale
    GetText.locale = 'de'

    toasts.clear
    app.window.window.lookup_action('take-picture').activate(nil)
    d.check('the no-camera toast comes back in German') { toasts == ['Bild konnte nicht aufgenommen werden'] }

    shutter = app.window.send(:camera).send(:camera_controls).send(:shutter_button)
    shutter.shutter_mode = Enums::ShutterMode::VIDEO
    d.check('the shutter tooltip translates too') { shutter.build.tooltip_text == 'Aufnahme starten' }
    shutter.shutter_mode = Enums::ShutterMode::PICTURE

    GetText.locale = original_locale
    toasts.clear
  end

  d.step('a countdown delays the shutter instead of firing it immediately') do
    toasts.clear
    app.settings.set_int('countdown', 1)
    d.check('the shutter button picked up the new countdown') do
      app.window.send(:camera).send(:camera_controls).send(:shutter_button).countdown == 1
    end

    app.window.window.lookup_action('take-picture').activate(nil)
    d.check('the countdown is running') { app.window.send(:countdown_active?) }
    d.check('no toast fired yet') { toasts.empty? }
  end

  d.step('pressing the shutter again while counting down cancels it') do
    app.window.window.lookup_action('take-picture').activate(nil)
    d.check('the countdown stopped') { !app.window.send(:countdown_active?) }
    d.check('still nothing was taken') { toasts.empty? }
  end

  d.step('starting the countdown again and letting it run fires the shutter') do
    app.window.window.lookup_action('take-picture').activate(nil)
    d.check('counting down again') { app.window.send(:countdown_active?) }
  end

  d.step('after the countdown elapses') do
    pump(1300)
    d.check('the countdown finished on its own') { !app.window.send(:countdown_active?) }
    d.check('the shutter fired, refused with no camera') { toasts == ['Could not take picture'] }
  end

  d.step('video capture mode refuses recording the same way') do
    toasts.clear
    app.settings.set_int('countdown', 0)
    app.settings.set_enum('capture-mode', Enums::CaptureMode::VIDEO)
    app.window.window.lookup_action('take-picture').activate(nil)
    d.check('the toast is the no-camera recording one') { toasts == ['Could not record video'] }
    d.check('recording never actually started') { !app.window.send(:camera).is_recording_active? }
    app.settings.set_enum('capture-mode', Enums::CaptureMode::PICTURE)
  end

  d.step('QR-detection mode hides the shutter and gallery button') do
    camera = app.window.send(:camera)
    controls = camera.send(:camera_controls)

    camera.set_capture_mode(Enums::CaptureMode::QR_DETECTION)
    d.check('the layout switched to detecting codes') do
      controls.layout == Enums::ControlsLayout::DETECTING_CODES
    end
    d.check('the shutter button is hidden') { !controls.send(:shutter_button).button.visible? }
    d.check('the gallery button stack is hidden') { !controls.send(:gallery_button_stack).visible? }
    d.check('the QR screen bin is enabled') { camera.send(:qr_screen_bin).enabled }
    pump(600)
    d.shot('02-qr-detection')

    camera.set_capture_mode(Enums::CaptureMode::PICTURE)
    d.check('switching back shows the shutter again') { controls.send(:shutter_button).button.visible? }
    d.check('and the gallery stack again') { controls.send(:gallery_button_stack).visible? }
    d.check('the layout is default again') { controls.layout == Enums::ControlsLayout::DEFAULT }
  end

  d.step('a CameraRow tracks its camera and the selection checkmark through the registry') do
    row = CameraRow.new
    built = row.build

    d.check('the row registered itself against the box it built') { CameraRow.for(built).equal?(row) }

    fake_camera = Struct.new(:display_name).new('Integrated Camera')
    row.item = fake_camera
    d.check('the label took the camera\'s display name') { row.send(:label).label == 'Integrated Camera' }
    d.check('item reads back the same camera') { row.item.equal?(fake_camera) }

    d.check('the checkmark starts hidden') { !row.selected? }
    row.selected = true
    d.check('selecting shows the checkmark') { row.selected? }
    row.selected = false
    d.check('deselecting hides it again') { !row.selected? }

    CameraRow.unregister(built)
    d.check('unregistering drops it from the registry') { CameraRow.for(built).nil? }
  end

  d.step('the camera controls orientation setter updates its own margins') do
    controls = app.window.send(:camera).send(:camera_controls)
    box = controls.box

    controls.orientation = :vertical
    d.check('vertical margins are set') { box.margin_top == 12 && box.margin_bottom == 12 }
    d.check('horizontal margins are cleared') { box.margin_start.zero? && box.margin_end.zero? }

    controls.orientation = :horizontal
    d.check('horizontal margins are back') { box.margin_start == 12 && box.margin_end == 12 }
    d.check('vertical margins are cleared') { box.margin_top.zero? && box.margin_bottom.zero? }
  end

  d.step('the shutter button retargets its tooltip per mode') do
    shutter = app.window.send(:camera).send(:camera_controls).send(:shutter_button)

    shutter.shutter_mode = Enums::ShutterMode::VIDEO
    d.check('video tooltip') { shutter.build.tooltip_text == 'Start Recording' }
    shutter.shutter_mode = Enums::ShutterMode::RECORDING
    d.check('recording tooltip') { shutter.build.tooltip_text == 'Stop Recording' }
    shutter.shutter_mode = Enums::ShutterMode::PICTURE
    d.check('back to picture tooltip') { shutter.build.tooltip_text == 'Take Picture' }
  end

  d.step('the preferences dialog opens with upstream\'s rows') do
    app.window.window.lookup_action('preferences').activate(nil)
  end

  d.step('its rows and groups match the ported gschema') do
    app.window.visible_dialog.then do |dialog|
      d.check('a PreferencesWindow is showing') { dialog.is_a?(PreferencesWindow) }
      d.check('the experimental group is hidden (no hardware encoding predicate)') do
        !dialog.send(:experimental_group).visible?
      end
      d.check('the shutter-sound row is wired to its action') do
        dialog.send(:shutter_sound_row).action_name == 'preferences-window.play-shutter-sound'
      end
      d.check('the guidelines row is wired to its action') do
        dialog.send(:guidelines_row).action_name == 'preferences-window.show-composition-guidelines'
      end
      d.check('the record-audio row is wired, recording is not active') do
        dialog.send(:record_audio_row).action_name == 'preferences-window.enable-audio-recording'
      end
      d.shot('03-preferences')

      d.check('play-shutter-sound starts true') { app.settings.play_shutter_sound? }
      dialog.send(:action_group).lookup_action('play-shutter-sound').activate(nil)
      d.check('toggling the row\'s action flips the real setting') { !app.settings.play_shutter_sound? }
      dialog.send(:action_group).lookup_action('play-shutter-sound').activate(nil)
      d.check('and flips it back') { app.settings.play_shutter_sound? }
    end
  end

  d.step('closing preferences and opening the about dialog') do
    app.window.visible_dialog&.close
    app.window.window.lookup_action('about').activate(nil)
  end

  d.step('the about dialog carries the metainfo-derived fields') do
    app.window.visible_dialog.then do |dialog|
      d.check('an AboutDialog is showing') { dialog.is_a?(AboutDialog) }
      d.check('its application id is the icon name') { dialog.application_icon == 'org.gnome.Snapshot' }
      d.check('its version has no pre-release suffix') { dialog.version == Snapshot::Rb::VERSION.split('-').first }
      d.check('its license is GPL-3.0') { dialog.license_type == :gpl_3_0 }
      d.check('its website is upstream\'s') { dialog.website == AboutDialog::WEBSITE }
      d.check('its developer name is upstream\'s') { dialog.developer_name == AboutDialog::DEVELOPER_NAME }
      # Now that gettext is wired (see lib/i18n.rb), this resolves through
      # the real catalogue for whatever locale built the dialog — which, in
      # this environment, is a real en_GB credits line, not the bare
      # "translator-credits" marker a from-scratch, untranslated build would
      # show. Either is correct; what matters is that it is never empty.
      d.check('translator credits resolve to something, not an empty string') do
        !dialog.translator_credits.to_s.empty?
      end
      d.check('debug info names the libraries, with no camera section') do
        info = Utils.debug_info(cameras: [])
        info.include?('Library Details') && info.include?('Gtk ') && info.include?('GStreamer ') &&
          !info.include?('Cameras:')
      end
      d.check('the GStreamer line is gstreamer_pbutils\'s own plugins-base version, not a placeholder') do
        real_version = "#{GstPbutils::PLUGINS_BASE_VERSION_MAJOR}." \
          "#{GstPbutils::PLUGINS_BASE_VERSION_MINOR}." \
          "#{GstPbutils::PLUGINS_BASE_VERSION_MICRO}"
        Utils.debug_info(cameras: []).include?("GStreamer #{real_version}")
      end
      d.shot('04-about')
    end
    app.window.visible_dialog&.close
  end

  d.step('the app.shortcuts action opens the shortcuts dialog') do
    app.app.lookup_action('shortcuts').activate(nil)
  end

  d.step('it carries upstream\'s three sections and twelve items') do
    app.window.visible_dialog.then do |dialog|
      d.check('a ShortcutsDialog is showing') { dialog.is_a?(ShortcutsDialog) }

      # Adwaita::ShortcutsDialog/ShortcutsSection expose `add` only — no
      # reader for what was added — so the structure itself (titles, item
      # counts, which items are action-bound vs literal) is checked against
      # the table the dialog was actually built from, a plain data check
      # with no widget needed; that the dialog *built* at all from it,
      # without raising, is what the step above already confirmed live.
      d.check('three sections, named General/Camera/Gallery') do
        ShortcutsDialog::SECTIONS.keys == %w[General Camera Gallery]
      end
      d.check('twelve items total, as upstream\'s shortcuts.ui has') do
        ShortcutsDialog::SECTIONS.values.sum(&:length) == 12
      end
      d.check('win.take-picture is bound as an action, not a literal key') do
        ShortcutsDialog::SECTIONS['Camera'].find { |(title, _accel, _action)| title == 'Take Picture or Start Recording' }
                                            .then { |(_title, accel, action)| accel.nil? && action == 'win.take-picture' }
      end
      d.check('"C" is a literal accelerator (focus/mode items carry no action)') do
        ShortcutsDialog::SECTIONS['Camera'].find { |(title, _accel, _action)| title == 'Show/Hide Composition Guidelines' }
                                            .then { |(_title, accel, action)| accel == 'C' && action.nil? }
      end
      d.shot('05-shortcuts')
    end
    app.window.visible_dialog&.close
  end

  d.step('the app registered its own accelerators, parsed the same as upstream\'s') do
    Snapshot::Application::ACCELS.each do |action, accels|
      d.check("#{action} resolves to #{accels.first}") do
        app.app.get_accels_for_action(action).map { |accel| Gtk.accelerator_parse(accel) } ==
          accels.map { |accel| Gtk.accelerator_parse(accel) }
      end
    end
    d.check('win.preferences is bound at the app level') do
      app.app.get_accels_for_action('win.preferences') == ['<Control>comma']
    end
    d.check('win.take-picture is bound at the app level') do
      app.app.get_accels_for_action('win.take-picture') == ['t']
    end
  end

  d.step('the stylesheet parses with no errors swallowed') do
    [].then do |errors|
      Gtk::CssProvider.new.tap do |provider|
        provider.signal_connect('parsing-error') { |_p, _section, error| errors << error.message }
        provider.load_from_string(Style::CSS)
      end
      d.check('the whole sheet parses cleanly') { errors.empty? }
    end
    d.check('every class the widgets add is one the sheet actually matches') do
      Style::APPLIED_CLASSES.all? { |cls| Style::CSS.include?(".#{cls}") }
    end
  end

  d.step('Utils names files and the context menu the way upstream does') do
    d.check('a picture file name has the right shape and extension') do
      Utils.picture_file_name =~ /\A(Photo from .+|Photo \d+)\.jpeg\z/
    end
    d.check('a video file name has the right shape and extension') do
      Utils.video_file_name(:h264mp4) =~ /\A(Recording from .+|Recording \d+)\.mp4\z/
    end
    d.check('the picture context menu offers Copy Picture') do
      menu = Utils.gallery_item_menu(true)
      menu.get_item_attribute_value(0, 'label', nil) == '_Copy Picture'
    end
    d.check('the video context menu offers Copy Video') do
      menu = Utils.gallery_item_menu(false)
      menu.get_item_attribute_value(0, 'label', nil) == '_Copy Video'
    end
  end

  d.step('Settings round-trips every key through its own JSON file') do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'settings.json')
      first = Settings.new(path: path)
      first.set_boolean('play-shutter-sound', false)
      first.set_int('countdown', 5)
      first.set_enum('capture-mode', Enums::CaptureMode::VIDEO)

      reloaded = Settings.new(path: path)
      d.check('a boolean survives a reload') { !reloaded.play_shutter_sound? }
      d.check('an int survives a reload') { reloaded.countdown == 5 }
      d.check('an enum survives a reload, by nick') { reloaded.enum_('capture-mode') == Enums::CaptureMode::VIDEO }
      d.check('an untouched key keeps its default') { reloaded.enable_audio_recording? }
    end
  end

  d.step('Enums fall back to their default for anything out of range') do
    d.check('CaptureMode.from_value(99) is the default') { Enums::CaptureMode.from_value(99) == Enums::CaptureMode.default }
    d.check('CaptureMode default is :picture') { Enums::CaptureMode.default == Enums::CaptureMode::PICTURE }
    d.check('nick round-trips') { Enums::CaptureMode.from_nick('qr-detection') == Enums::CaptureMode::QR_DETECTION }
    d.check('an unknown nick is the default') { Enums::CaptureMode.from_nick('nonsense') == Enums::CaptureMode.default }
  end

  d.step('opening the gallery with nothing captured is empty but does not crash') do
    app.window.window.lookup_action('toggle-gallery').activate(nil)
  end

  d.step('the empty gallery page is showing') do
    d.check('the gallery page is now visible') do
      app.window.send(:navigation_view).visible_page.equal?(app.window.send(:gallery_page))
    end
    d.check('it has no pages yet') { app.window.send(:gallery).items.empty? }
    d.shot('06-empty-gallery')
    app.window.window.lookup_action('toggle-gallery').activate(nil)
    d.check('popping back shows the camera page again') do
      app.window.send(:navigation_view).visible_page.equal?(app.window.send(:camera_page))
    end
  end

  d.step('a real captured picture decodes, thumbnails, and enables the gallery button') do
    picture_path = File.join(Utils.pictures_dir, 'drive-picture.png')
    write_test_picture(picture_path)
    file = Gio::File.new_for_path(picture_path)

    gallery = app.window.send(:gallery)
    item = gallery.add_image(file)

    d.check('the gallery picked it up') { gallery.items.length == 1 }
    d.check('it loaded, since add_image always loads') { item.loaded? }
    d.check('it decoded a real thumbnail') { !item.thumbnail.nil? }
    d.check('the toggle-gallery action is enabled now that an item exists') do
      app.window.window.lookup_action('toggle-gallery').enabled?
    end
    d.check('the gallery button swapped away from the placeholder') do
      app.window.send(:camera).send(:camera_controls).send(:gallery_button_stack)
         .visible_child_name == 'gallery-button'
    end
  end

  d.step('a broken video file is handled without raising') do
    video_path = File.join(Utils.videos_dir, 'drive-broken.webm')
    File.write(video_path, 'not a real video stream')
    file = Gio::File.new_for_path(video_path)

    gallery = app.window.send(:gallery)
    item = gallery.add_video(file)

    d.check('the gallery still accepted it') { gallery.items.length == 2 }
    d.check('it is marked loaded even with nothing to decode') { item.loaded? }
    d.check('no thumbnail, but no crash either') { item.thumbnail.nil? }

    player = item.send(:video_player)
    d.check('GalleryVideo built a real VideoPlayer') { player.is_a?(VideoPlayer) }
    d.check('stream exposes the underlying Gtk::MediaFile') { player.stream.is_a?(Gtk::MediaFile) }
    d.check('pausing an unrealized, unparented player does not raise') do
      player.pause
      true
    rescue StandardError
      false
    end
  end

  d.step('opening the gallery now jumps straight to the newest item') do
    app.window.window.lookup_action('toggle-gallery').activate(nil)
  end

  d.step('the newest item (the video, prepended last) is current') do
    gallery = app.window.send(:gallery)
    d.check('two items in the gallery') { gallery.items.length == 2 }
    d.check('the video is first (prepend order)') { gallery.items.first.is_a?(GalleryVideo) }
    d.check('the current page is the newest one') { gallery.items.first.equal?(gallery.send(:sliding_view).current_page) }
    pump(300)
    d.shot('07-gallery-with-items')
  end

  d.step('the gallery\'s previous/next buttons walk between the two items') do
    gallery = app.window.send(:gallery)
    prev_button = gallery.send(:prev_button)
    next_button = gallery.send(:next_button)

    # The newest item (the video) sits at index 0; SlidingView's prev_page
    # only exists for a positive index, so starting on the newest item
    # disables "previous" and leaves "next" (toward the older picture)
    # enabled — upstream's own prepend-newest-first ordering, not a port bug.
    d.check('previous is disabled (already on the newest item)') { !prev_button.sensitive? }
    d.check('next is enabled (there is an older item)') { next_button.sensitive? }

    next_button.signal_emit('clicked')
    pump(200)
    d.check('moved on to the picture') { gallery.send(:sliding_view).current_page.is_a?(GalleryPicture) }
    d.check('next is disabled now (the picture is the oldest item)') { !gallery.send(:next_button).sensitive? }
    d.check('previous is enabled now') { gallery.send(:prev_button).sensitive? }
    d.shot('08-gallery-next-item')
  end

  d.step('the gallery.copy GAction (not just the Ruby method) is reachable') do
    gallery = app.window.send(:gallery)
    bin = gallery.send(:breakpoint_bin)
    before = gallery.send(:sliding_view).current_page.file.path
    copy_calls = 0
    gallery.define_singleton_method(:copy) { |*| copy_calls += 1; true }

    # Utils.gallery_item_menu's Gio::Menu names "gallery.copy" / "gallery.delete".
    # Firing it through Gtk::Widget#activate_action (the same resolution path
    # GTK uses for a clicked menu item) — not calling Gallery#copy directly —
    # is what proves the action group inserted in Gallery#build is actually
    # reachable from the widget tree, which is the bug component-parity.md
    # flagged: the menu offered these actions but nothing had ever installed
    # them, so clicking either did nothing.
    bin.activate_action('gallery.copy', nil)
    d.check('activating gallery.copy invoked Gallery#copy') { copy_calls == 1 }
    d.check('the current item is unchanged by copying') { gallery.send(:sliding_view).current_page.file.path == before }
  end

  d.step('the gallery.delete action removes the current item from the model and the disk') do
    gallery = app.window.send(:gallery)
    deleted_path = gallery.send(:sliding_view).current_page.file.path

    d.check('the file exists before deleting') { File.exist?(deleted_path) }
    gallery.send(:breakpoint_bin).activate_action('gallery.delete', nil)
    d.check('one item is left') { gallery.items.length == 1 }
    d.check('the file is gone from disk') { !File.exist?(deleted_path) }
  end

  d.step('deleting the last item (via the same gallery.delete action) closes the gallery and disables its action') do
    app.window.send(:gallery).send(:breakpoint_bin).activate_action('gallery.delete', nil)

    d.check('the gallery is empty') { app.window.send(:gallery).items.empty? }
    d.check('toggle-gallery disabled itself') { !app.window.window.lookup_action('toggle-gallery').enabled? }
    d.check('the view popped back to the camera page') do
      app.window.send(:navigation_view).visible_page.equal?(app.window.send(:camera_page))
    end
    d.check('the gallery button reverted to the placeholder') do
      app.window.send(:camera).send(:camera_controls).send(:gallery_button_stack)
         .visible_child_name == 'fake-gallery-button'
    end
    pump(200)
    d.shot('09-back-to-empty')
  end
end
