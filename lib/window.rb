# frozen_string_literal: true

require 'adwaita'

require_relative 'enums'
require_relative 'settings'
require_relative 'camera'
require_relative 'gallery'
require_relative 'about_dialog'
require_relative 'preferences_window'
require_relative 'utils'
require_relative 'snapshot/rb/version'

# Window is the app's main window, a port of src/widgets/window.rs and
# data/resources/ui/window.ui: an Adwaita::ApplicationWindow holding a toast
# overlay over an Adwaita::NavigationView, which pages between the Camera and
# the Gallery.
#
# Application built this shell inline before this file existed; it now owns
# the camera/gallery pages, the countdown timer, the window actions whose
# handlers need those pages (take-picture, toggle-gallery, toggle-guidelines,
# about, preferences), and the window-size persistence Settings already knew
# how to apply/remember. Application keeps only the actions that do not need
# a camera or a gallery (quit, shortcuts) and the app-wide setup.
class Window
  def initialize(app, settings:)
    @app = app
    @settings = settings
    @countdown_timer_id = nil
  end

  def build
    window.tap do |win|
      win.content = toast_overlay
      toast_overlay.child = navigation_view

      navigation_view.add(camera_page)
      navigation_view.add(gallery_page)

      camera_page.signal_connect('hidden') { on_camera_page_hidden }
      camera_page.signal_connect('showing') { on_camera_page_showing }

      win.signal_connect('close-request') do
        @settings.remember(win)
        false
      end

      win.signal_connect('notify::is-active') { on_is_active_changed }
      win.signal_connect('notify::suspended') { on_suspended_changed }

      @settings.apply_to(win)
      setup_actions
      setup_accels

      camera.set_capture_mode(capture_mode)
      camera.set_countdown(@settings.countdown)
      camera.set_gallery(gallery)

      @settings.connect_changed('countdown') do
        countdown_cancel
        camera.set_countdown(@settings.countdown)
      end
    end
  end

  def present = window.present

  def send_toast(text) = toast_overlay.add_toast(Adwaita::Toast.new(text))

  def set_shutter_enabled(enabled) = window.action_set_enabled('win.take-picture', enabled)

  def inhibit(reason)
    uninhibit
    cookie = @app.inhibit(window, Gtk::ApplicationInhibitFlags::IDLE, reason)
    @inhibit_cookie = cookie if cookie.positive?
  end

  def uninhibit
    cookie = @inhibit_cookie
    return unless cookie

    @app.uninhibit(cookie)
    @inhibit_cookie = nil
  end

  def visible_dialog = window.visible_dialog

  # The underlying Adwaita::ApplicationWindow, for anything outside this
  # class — Application's shortcuts action, and PreferencesWindow/AboutDialog
  # below — that needs a parent to present a dialog against.
  def window
    @window ||= Adwaita::ApplicationWindow.new(@app).tap { |win| win.title = 'Camera' }
  end

  private

    # Memoized widget methods

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

    def navigation_view = @navigation_view ||= Adwaita::NavigationView.new

    def camera_page = @camera_page ||= Adwaita::NavigationPage.new(camera.build, 'Camera')

    def gallery_page = @gallery_page ||= Adwaita::NavigationPage.new(gallery.build, 'Gallery')

    def camera
      @camera ||= Camera.new(settings: @settings, on_toast: ->(text) { send_toast(text) })
    end

    def gallery
      @gallery ||= Gallery.new.tap do |g|
        g.connect_item_added { |_, _item| window.action_set_enabled('win.toggle-gallery', true) }
        g.connect_item_removed do |_, _is_last|
          if g.items.empty?
            window.action_set_enabled('win.toggle-gallery', false)
            navigation_view.pop
          end
        end
      end
    end

    def setup_actions
      window.add_action(simple_action('preferences') { show_preferences })
      window.add_action(simple_action('about') { show_about_dialog })
      window.add_action(simple_action('take-picture') { on_take_picture })
      window.add_action(simple_action('toggle-guidelines') { camera.toggle_guidelines })
      window.add_action(simple_action('toggle-gallery') { toggle_gallery })
      window.add_action(@settings.create_action('countdown'))
    end

    def setup_accels
      @app.set_accels_for_action('win.preferences', ['<Control>comma'])
      @app.set_accels_for_action('win.take-picture', ['t'])
      @app.set_accels_for_action('win.toggle-guidelines', ['c'])
    end

    def simple_action(name, &block)
      Gio::SimpleAction.new(name).tap { |action| action.signal_connect('activate') { block.call } }
    end

    def toggle_gallery
      if navigation_view.visible_page == camera_page
        navigation_view.push(gallery_page)
        gallery.open
      else
        navigation_view.pop
      end
    end

    def on_camera_page_hidden
      camera.stop_recording if camera.is_recording_active?
      camera.set_page_visible(false)
      camera.stop_stream

      case capture_mode
      when Enums::CaptureMode::PICTURE
        camera.set_shutter_mode(Enums::ShutterMode::PICTURE)
      when Enums::CaptureMode::VIDEO
        camera.set_shutter_mode(Enums::ShutterMode::VIDEO)
      end

      set_shutter_enabled(false)
    end

    def on_camera_page_showing
      camera.set_page_visible(true)
      camera.start_stream
      set_shutter_enabled(true)
    end

    def on_is_active_changed
      camera.start_stream if window.active?
    end

    def on_suspended_changed
      if window.suspended? && !camera.is_recording_active?
        camera.set_page_visible(false)
        camera.stop_stream
      else
        camera.set_page_visible(true)
        camera.start_stream
      end
    end

    def capture_mode = @settings.enum_('capture-mode')

    def countdown_active? = !@countdown_timer_id.nil?

    def countdown_cancel
      source_id = @countdown_timer_id
      @countdown_timer_id = nil
      GLib::Source.remove(source_id) if source_id

      camera.stop_countdown
    end

    def countdown_start
      return if countdown_active?

      duration = @settings.countdown
      camera.set_countdown(duration)
      camera.start_countdown

      @countdown_timer_id = GLib::Timeout.add_seconds(duration) do
        @countdown_timer_id = nil
        shutter_action
        camera.stop_countdown
        false
      end
    end

    def shutter_action
      if capture_mode == Enums::CaptureMode::VIDEO
        if camera.is_recording_active?
          set_shutter_enabled(false)
          camera.stop_recording
          set_shutter_enabled(true)
        else
          camera.start_recording
        end
      else
        format = @settings.enum_('picture-format')
        camera.take_picture(format)
      end
    end

    def on_take_picture
      if camera.is_recording_active?
        shutter_action
      elsif @settings.countdown.positive?
        countdown_active? ? countdown_cancel : countdown_start
      else
        shutter_action
      end
    end

    def show_preferences
      return if visible_dialog

      PreferencesWindow.new(@settings, is_app_recording: camera.is_recording_active?).build.present(window)
    end

    def show_about_dialog
      AboutDialog.new(version: Rb::VERSION).build.present(window)
    end
end
