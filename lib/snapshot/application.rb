# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative '../enums'
require_relative '../settings'
require_relative '../style'
require_relative '../utils'
require_relative '../flash_bin'
require_relative '../guidelines_bin'
require_relative '../qr_screen_bin'
require_relative '../shutter_button'
require_relative '../camera_row'
require_relative '../qr_bottom_sheet'
require_relative '../preferences_window'
require_relative '../shortcuts_dialog'
require_relative '../about_dialog'
require_relative 'rb/version'

module Snapshot
  # Application is the port's entry point, ported from src/application.rs and
  # src/main.rs: it names itself org.gnome.Snapshot, forces the dark colour
  # scheme the way upstream does, installs the stylesheet, registers the
  # actions and accelerators upstream registers, and puts up the window.
  #
  # What it assembles is the shell upstream's window and camera page share: the
  # toast overlay, the primary menu, the three overlay bins that wrap the
  # viewfinder, and the window actions whose handlers do not need a camera. The
  # camera and gallery pages go inside the bins, and replace their content
  # rather than the shell around them.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    APP_ID = 'org.gnome.Snapshot'

    # Upstream's set_accels_for_action calls, in src/application.rs.
    ACCELS = {
      'app.quit'              => ['<Control>q'],
      'app.shortcuts'         => ['<Control>question'],
      'win.preferences'       => ['<Control>comma'],
      'window.close'          => ['<Control>w'],
      'win.take-picture'      => ['t'],
      'win.toggle-guidelines' => ['c'],
    }.freeze

    def initialize(settings: nil, app_id: APP_ID, flags: :default_flags, present: true)
      @settings = settings || Settings.new
      @app_id = app_id
      @flags = flags
      @present = present
    end

    attr_reader :settings

    def build
      app.tap do
        app.signal_connect('startup') { on_startup }

        app.signal_connect('activate') do
          window.tap do |win|
            win.content = toast_overlay
          end

          toast_overlay.tap do |overlay|
            overlay.child = toolbar_view
          end

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.add_bottom_bar(controls_box)
            view.content = flash_bin.build

            header_bar.pack_end(menu_button)

            controls_box.append(shutter_button.build)
          end

          flash_bin.child = guidelines_bin.build
          guidelines_bin.child = qr_screen_bin.build
          qr_screen_bin.child = camera_status_page

          if @present
            window.present
          end
        end
      end
    end

    def run = app.run([])

    # Upstream's Window::send_toast.
    def send_toast(text)
      toast_overlay.add_toast(Adwaita::Toast.new(text))
    end

    # Adwaita::Application is broken in the Ruby bindings, so the application
    # object comes from Gtk; the window is Adwaita's.
    def app = @app ||= Gtk::Application.new(@app_id, @flags)

    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = 'Camera'
        @settings.apply_to(win)
        win.signal_connect('close-request') do
          @settings.remember(win)
          false
        end
      end
    end

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = 'open-menu-symbolic'
        button.tooltip_text = 'Main Menu'
        button.primary = true
        button.menu_model = primary_menu
      end
    end

    # Upstream's primary menu, in data/resources/ui/camera.ui.
    def primary_menu
      @primary_menu ||= Gio::Menu.new.tap do |menu|
        menu.append('_Preferences', 'win.preferences')
        menu.append('_Keyboard Shortcuts', 'app.shortcuts')
        menu.append('_About Camera', 'win.about')
      end
    end

    # The bottom control row of upstream's camera page. The camera chooser and
    # the gallery button join the shutter here once the camera backend and the
    # gallery land; the frame and the shutter are what the shell can show on
    # its own.
    def controls_box
      @controls_box ||= Gtk::Box.new(:horizontal, 24).tap do |box|
        box.halign = :center
        box.valign = :center
        box.add_css_class('controlsframe')
        box.add_css_class('bottom')
      end
    end

    # The shutter, wired to the action upstream wires it to.
    def shutter_button
      @shutter_button ||= ShutterButton.new.tap do |shutter|
        shutter.button.action_name = 'win.take-picture'
        shutter.shutter_mode = shutter_mode
        shutter.countdown = @settings.countdown
      end
    end

    # Upstream's Window::on_camera_page_hidden picks the shutter mode off the
    # capture mode the same way.
    def shutter_mode
      (@settings.enum_('capture-mode') == Enums::CaptureMode::VIDEO).then do |recording|
        if recording
          Enums::ShutterMode::VIDEO
        else
          Enums::ShutterMode::PICTURE
        end
      end
    end

    # The three overlay bins the camera page stacks over the viewfinder.
    def flash_bin = @flash_bin ||= FlashBin.new

    def guidelines_bin
      @guidelines_bin ||= GuidelinesBin.new(
        draw_guidelines: @settings.show_composition_guidelines?,
      )
    end

    def qr_screen_bin
      @qr_screen_bin ||= QrScreenBin.new(
        enabled: @settings.enum_('capture-mode') == Enums::CaptureMode::QR_DETECTION,
      )
    end

    # Upstream's "no camera found" state, the not-found page of the camera
    # page's stack. It is what a machine without a camera sees, and it is what
    # this port shows until the viewfinder lands.
    def camera_status_page
      @camera_status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = 'No Camera Found'
        page.description = 'Connect a camera to take pictures and videos'
        page.icon_name = 'camera-photo-symbolic'
      end
    end

    private

      def on_startup
        Gtk::Window.set_default_icon_name(@app_id)
        Adwaita::StyleManager.default.color_scheme = :force_dark
        Style.load

        setup_actions
        setup_accels
      end

      # The window actions of upstream's src/widgets/window.rs, less the two
      # whose handlers need the camera and gallery pages.
      def setup_actions
        app.add_action(quit_action)
        app.add_action(shortcuts_action)
        window.add_action(preferences_action)
        window.add_action(about_action)
        window.add_action(take_picture_action)
        window.add_action(toggle_guidelines_action)
        window.add_action(@settings.create_action('countdown'))

        # Upstream re-arms the shutter's ring whenever the countdown changes
        # under it.
        @settings.connect_changed('countdown') do
          shutter_button.countdown = @settings.countdown
        end
      end

      def setup_accels
        ACCELS.each { |name, accels| app.set_accels_for_action(name, accels) }
      end

      def quit_action
        Gio::SimpleAction.new('quit').tap do |action|
          action.signal_connect('activate') { app.quit }
        end
      end

      def shortcuts_action
        Gio::SimpleAction.new('shortcuts').tap do |action|
          action.signal_connect('activate') do
            ShortcutsDialog.new.build.present(window)
          end
        end
      end

      def preferences_action
        Gio::SimpleAction.new('preferences').tap do |action|
          action.signal_connect('activate') { show_preferences }
        end
      end

      # Upstream refuses to stack a second dialog on the window.
      def show_preferences
        window.visible_dialog.then do |existing|
          unless existing
            PreferencesWindow.new(@settings).build.present(window)
          end
        end
      end

      def about_action
        Gio::SimpleAction.new('about').tap do |action|
          action.signal_connect('activate') do
            AboutDialog.new(version: Rb::VERSION).build.present(window)
          end
        end
      end

      # Upstream's win.take-picture reports the failure as a toast when the
      # capture cannot be made, which with no camera attached is every time.
      def take_picture_action
        Gio::SimpleAction.new('take-picture').tap do |action|
          action.signal_connect('activate') { send_toast('Could not take picture') }
        end
      end

      # Upstream's win.toggle-guidelines, accelerator "c": it flips the bin and
      # the setting it is bound to together.
      def toggle_guidelines_action
        Gio::SimpleAction.new('toggle-guidelines').tap do |action|
          action.signal_connect('activate') do
            guidelines_bin.toggle
            @settings.set_boolean('show-composition-guidelines', guidelines_bin.draw_guidelines)
          end
        end
      end
  end
end
