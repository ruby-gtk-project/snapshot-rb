# frozen_string_literal: true

require 'adwaita'

require_relative 'settings'

# PreferencesWindow is the preferences dialog, ported from
# src/widgets/preferences_window.rs and data/resources/ui/preferences_window.ui:
# an AdwPreferencesDialog holding one page, three groups and four switch rows.
#
# Every row is driven by an action rather than by a bound property, exactly as
# upstream does: the settings object hands out a stateful action per key, the
# actions go into a "preferences-window" group on the dialog, and each row
# names its action. The two recording keys only get an action while no
# recording is running, which is how upstream makes those rows inert mid-take —
# a row whose action is missing is insensitive on its own.
#
# The Experimental group is shown only where hardware video encoding works.
# Upstream asks aperture, which asks GStreamer's registry whether an H.264 or
# VP8 hardware encoder element exists — a `Gst::ElementFactory.find` lookup.
# This port does bind GStreamer now (gstreamer_pbutils), but it does not bind
# `Gst::ElementFactory`: that lookup belongs to GStreamer core itself, which
# is the separate `gstreamer` gem, not one of this port's bindings. So the
# group still stays hidden rather than guess; the predicate remains a
# constructor argument so a camera backend that can answer it can be wired in
# without changing this file again.
#
class PreferencesWindow < Adwaita::PreferencesDialog
  CONTENT_WIDTH = 360

  # The two keys that are only actionable while nothing is recording.
  RECORDING_KEYS = %w[enable-audio-recording enable-hardware-encoding].freeze

  ALWAYS_KEYS = %w[play-shutter-sound show-composition-guidelines].freeze

  def initialize(settings, is_app_recording: false, hardware_encoding_supported: false)
    super()
    @settings = settings
    @is_app_recording = is_app_recording
    @hardware_encoding_supported = hardware_encoding_supported
  end

  attr_reader :is_app_recording

  def build
    tap do |dialog|
      dialog.insert_action_group('preferences-window', action_group)
      dialog.add(general_page)

      general_page.tap do |page|
        page.add(general_group)
        page.add(video_group)
        page.add(experimental_group)

        general_group.tap do |group|
          group.add(shutter_sound_row)
          group.add(guidelines_row)
        end

        video_group.add(record_audio_row)
        experimental_group.add(hardware_encoding_row)
      end
    end
  end

  # Memoized widget methods

  def general_page
    @general_page ||= Adwaita::PreferencesPage.new.tap do |page|
      page.title = 'General'
      page.icon_name = 'applications-system-symbolic'
    end
  end

  def general_group
    @general_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'General'
    end
  end

  def video_group
    @video_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Video Recording'
    end
  end

  def experimental_group
    @experimental_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Experimental'
      group.description = 'Some graphic drivers may cause the system to be unstable or crash. ' \
                          'In these cases, reboot the system and disable the option.'
      group.visible = @hardware_encoding_supported
    end
  end

  def shutter_sound_row
    @shutter_sound_row ||= switch_row('_Shutter Sound', 'play-shutter-sound')
  end

  def guidelines_row
    @guidelines_row ||= switch_row('_Composition Guidelines', 'show-composition-guidelines')
  end

  def record_audio_row
    @record_audio_row ||= switch_row('_Record Audio', 'enable-audio-recording')
  end

  def hardware_encoding_row
    @hardware_encoding_row ||= switch_row('_Hardware Video Encoding', 'enable-hardware-encoding')
  end

  private

    def switch_row(title, key)
      Adwaita::SwitchRow.new.tap do |row|
        row.title = title
        row.use_underline = true
        row.action_name = "preferences-window.#{key}"
      end
    end

    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        actionable_keys.each { |key| group.add_action(@settings.create_action(key)) }
      end
    end

    def actionable_keys
      @is_app_recording.then do |recording|
        if recording
          ALWAYS_KEYS
        else
          ALWAYS_KEYS + RECORDING_KEYS
        end
      end
    end
end
