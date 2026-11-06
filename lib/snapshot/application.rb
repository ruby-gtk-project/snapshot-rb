# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

require_relative '../settings'
require_relative '../style'
require_relative '../window'
require_relative '../shortcuts_dialog'

module Snapshot
  # Application is the port's entry point, ported from src/application.rs and
  # src/main.rs: it names itself org.gnome.Snapshot, forces the dark colour
  # scheme the way upstream does, installs the stylesheet, and registers the
  # two actions and all the accelerators upstream registers at the app level
  # (quit and shortcuts; everything else is a window action, and Window
  # registers those itself).
  #
  # Everything the window, the camera and the gallery need — the toast
  # overlay, the navigation view, the control rows, the bins around the
  # viewfinder — now lives in Window (see window.rb); Application's whole job
  # is standing the app up and handing it one.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    APP_ID = 'org.gnome.Snapshot'

    # Upstream's set_accels_for_action calls that are not Window's to make,
    # in src/application.rs.
    ACCELS = {
      'app.quit'      => ['<Control>q'],
      'app.shortcuts' => ['<Control>question'],
      'window.close'  => ['<Control>w'],
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
          window.build

          if @present
            window.present
          end
        end
      end
    end

    def run = app.run([])

    def send_toast(text) = window.send_toast(text)

    # Adwaita::Application is broken in the Ruby bindings, so the application
    # object comes from Gtk; the window is Adwaita's.
    def app = @app ||= Gtk::Application.new(@app_id, @flags)

    def window = @window ||= Window.new(app, settings: @settings)

    private

      def on_startup
        Gtk::Window.set_default_icon_name(@app_id)
        Adwaita::StyleManager.default.color_scheme = :force_dark
        Style.load

        setup_actions
        setup_accels
      end

      def setup_actions
        app.add_action(quit_action)
        app.add_action(shortcuts_action)
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
          action.signal_connect('activate') { ShortcutsDialog.new.build.present(window.window) }
        end
      end
  end
end
