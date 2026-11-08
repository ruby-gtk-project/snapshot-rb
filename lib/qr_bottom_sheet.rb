# frozen_string_literal: true

require 'adwaita'

require_relative 'i18n'

# QrBottomSheet is what the camera raises when the viewfinder decodes a code, a
# port of src/widgets/qr_bottom_sheet.rs and
# data/resources/ui/qr_bottom_sheet.ui: a bin holding a "Code Detected"
# preferences group with one action row, a copy button, and an open-link button
# that only appears when the code turns out to be an http(s) URL.
#
# Both buttons are driven by the two actions upstream installs on the widget
# class, in the "qr-bottom-sheet" group: copy and open-external. Upstream
# reaches its window through the widget hierarchy to raise the toast; here the
# toast is sent through the on_toast callback the camera page passes in, so the
# sheet does not need to know what kind of root it is under.
#
class QrBottomSheet
  include Snapshot::I18n

  URL_SCHEMES = %w[https:// http://].freeze

  def initialize(on_toast: nil)
    @on_toast = on_toast
  end

  attr_reader :contents

  def build
    bin.tap do |root|
      root.insert_action_group('qr-bottom-sheet', action_group)
      root.child = group

      group.add(action_row)

      action_row.tap do |row|
        row.add_suffix(copy_button)
        row.add_suffix(open_external_button)
      end
    end
  end

  # Upstream's `contents` property: setting it fills the row's subtitle in and
  # decides whether the open-link button is there to be pressed.
  def contents=(value)
    (@contents == value).then do |unchanged|
      unless unchanged
        @contents = value
        action_row.subtitle = value.to_s
        open_external_button.visible = url?
      end
    end
  end

  def url? = URL_SCHEMES.any? { |scheme| @contents.to_s.start_with?(scheme) }

  # Memoized widget methods

  def bin = @bin ||= Adwaita::Bin.new

  def group
    @group ||= Adwaita::PreferencesGroup.new.tap do |preferences|
      preferences.title = _('Code Detected')
      preferences.margin_start = 12
      preferences.margin_end = 12
      preferences.margin_top = 36
      preferences.margin_bottom = 36
    end
  end

  def action_row
    @action_row ||= Adwaita::ActionRow.new.tap do |row|
      row.title = _('Contents')
      row.use_markup = false
      row.add_css_class('property')
    end
  end

  def copy_button
    @copy_button ||= Gtk::Button.new.tap do |button|
      button.valign = :center
      button.icon_name = 'edit-copy-symbolic'
      button.tooltip_text = _('Copy to Clipboard')
      button.action_name = 'qr-bottom-sheet.copy'
      button.add_css_class('flat')
    end
  end

  def open_external_button
    @open_external_button ||= Gtk::Button.new.tap do |button|
      button.valign = :center
      button.visible = false
      button.icon_name = 'external-link-symbolic'
      button.tooltip_text = _('Open Link')
      button.action_name = 'qr-bottom-sheet.open-external'
      button.add_css_class('flat')
    end
  end

  private

    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(copy_action)
        group.add_action(open_external_action)
      end
    end

    def copy_action
      Gio::SimpleAction.new('copy').tap do |action|
        action.signal_connect('activate') { copy }
      end
    end

    def open_external_action
      Gio::SimpleAction.new('open-external').tap do |action|
        action.signal_connect('activate') { open_external }
      end
    end

    def copy
      @contents.then do |text|
        if text
          bin.clipboard.set(text)
          @on_toast&.call(_('Copied to clipboard'))
        end
      end
    end

    # Upstream awaits the launcher and swallows the error GTK reports when the
    # user dismisses the chooser it may put up; anything else is logged.
    def open_external
      @contents.then do |uri|
        if uri
          Gtk::UriLauncher.new(uri).launch(root_window, nil) do |launcher, result|
            finish_launch(launcher, result)
          end
        end
      end
    end

    def finish_launch(launcher, result)
      launcher.launch_finish(result)
    rescue Gtk::DialogError => e
      e.code.then do |code|
        unless code == Gtk::DialogError::DISMISSED
          warn "Could not open external URI: #{e.message}"
        end
      end
    rescue GLib::Error => e
      warn "Could not open external URI: #{e.message}"
    end

    def root_window
      bin.root.then do |root|
        if root.is_a?(Gtk::Window)
          root
        end
      end
    end
end
