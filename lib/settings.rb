# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'gio2'

require_relative 'enums'

# Settings holds the ten keys and two enums of upstream's
# data/org.gnome.Snapshot.gschema.xml.in, with the same defaults and the same
# semantics.
#
# Upstream uses GSettings, which needs a compiled schema installed into the
# system's glib-2.0/schemas directory — requiring an install step before the
# app can run from a checkout is worse than the alternative, so the keys are
# backed by a small JSON file under XDG_CONFIG_HOME instead. The parts of the
# GSettings API the widgets actually use are kept: typed readers (#int,
# #boolean, #string, #enum_), #set_int / #set_boolean / #set_enum,
# #create_action for the switch rows and the countdown menu, and
# #connect_changed for the window's countdown watcher.
#
class Settings
  # key => [default, variant type]. The types are the ones in the gschema: "i"
  # for the two window dimensions and the countdown, "b" for the four
  # switches, "s" for the last camera id, and an enum module for the two keys
  # the gschema declares with `enum=`.
  KEYS = {
    'window-width'                => [800, 'i'],
    'window-height'               => [640, 'i'],
    'is-maximized'                => [false, 'b'],
    'play-shutter-sound'          => [true, 'b'],
    'show-composition-guidelines' => [false, 'b'],
    'enable-audio-recording'      => [true, 'b'],
    'enable-hardware-encoding'    => [false, 'b'],
    'countdown'                   => [0, 'i'],
    'capture-mode'                => ['picture', Enums::CaptureMode],
    'picture-format'              => ['jpeg', Enums::PictureFormat],
    'last-camera-id'              => ['', 's'],
  }.freeze

  DEFAULTS = KEYS.transform_values(&:first).freeze

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
    @watchers = {}
  end

  def location = @path

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = value
    write
    notify(key.to_s)
    value
  end

  # Typed readers, named as GSettings names them.

  def int(key) = self[key].to_i

  def boolean(key) = self[key] == true

  def string(key) = self[key].to_s

  # Upstream reads the two enum keys with `settings.enum_("capture-mode")`,
  # which hands back the numeric value; the Ruby port works in the enum's own
  # symbols, so #enum_ returns the member and #enum_value the number.
  def enum_(key) = enum_module(key).from_nick(self[key])

  def enum_value(key) = enum_module(key).to_value(enum_(key))

  def set_int(key, value) = self[key] = value.to_i

  def set_boolean(key, value) = self[key] = (value == true)

  def set_string(key, value) = self[key] = value.to_s

  def set_enum(key, member) = self[key] = enum_module(key).nick(member)

  # Named accessors for every key, so callers do not repeat the string keys.
  # countdown, window_width, play_shutter_sound?, and so on.
  KEYS.each_key do |key|
    method_name = key.tr('-', '_')
    define_method(method_name) { self[key] }
    define_method(:"#{method_name}=") { |value| self[key] = value }
    if DEFAULTS[key] == true || DEFAULTS[key] == false
      define_method(:"#{method_name}?") { self[key] == true }
    end
  end

  # The GSettings#connect_changed the window uses to re-arm its countdown when
  # the setting changes under it. The block is called with the key name.
  def connect_changed(key, &block)
    @watchers[key.to_s] ||= []
    @watchers[key.to_s] << block
    block
  end

  # GSettings#create_action: a stateful Gio action named after the key, whose
  # state is the key's value and whose change-state handler writes it back.
  # The switch rows in the preferences window and the countdown radio items in
  # the camera menu are both driven this way.
  #
  # GSettings shapes the action by the key's type, and so does this: a boolean
  # key makes a parameterless action that toggles when activated, which is what
  # a switch row drives, while any other key takes its own type as the
  # parameter, which is what a radio item in a menu passes.
  def create_action(key)
    Gio::SimpleAction.new(
      key.to_s,
      action_parameter_type(key),
      variant(key),
    ).tap do |action|
      # The Ruby bindings hand the handler the unwrapped value rather than the
      # GLib::Variant the C signal carries.
      action.signal_connect('change-state') do |_, value|
        self[key] = unwrap(value)
      end

      action.signal_connect('activate') { |target, value| activate(target, key, value) }

      connect_changed(key) { action.set_state(variant(key)) }
    end
  end

  # Restores the geometry the previous run recorded, upstream's
  # Window::load_window_size.
  def apply_to(window)
    window.set_default_size(int('window-width'), int('window-height'))

    boolean('is-maximized').then do |maximized|
      if maximized
        window.maximize
      end
    end
  end

  # Records the geometry, upstream's Window::save_window_size. Upstream writes
  # the default size whatever the state; doing the same here means a maximized
  # window is restored maximized at the size it had before.
  def remember(window)
    @values['window-width'] = window.default_width
    @values['window-height'] = window.default_height
    @values['is-maximized'] = window.maximized?
    write
  end

  # The enum keys hold their nick on disk, which is a string to GLib; every
  # other key holds its own type.
  def variant_type(key)
    KEYS.fetch(key.to_s).last.then do |type|
      if type.is_a?(String)
        type
      else
        's'
      end
    end
  end

  private

    def variant(key) = GLib::Variant.new(self[key], variant_type(key))

    # A boolean key's action takes no parameter, so that activating it toggles.
    def action_parameter_type(key)
      (variant_type(key) == 'b').then do |toggle|
        if toggle
          nil
        else
          GLib::VariantType.new(variant_type(key))
        end
      end
    end

    # GSettings' own activate behaviour: a parameterless boolean action
    # toggles, anything else changes state to the parameter it was given.
    def activate(action, key, value)
      value.then do |parameter|
        if parameter.nil?
          action.change_state(GLib::Variant.new(!boolean(key), 'b'))
        else
          action.change_state(GLib::Variant.new(unwrap(parameter), variant_type(key)))
        end
      end
    end

    def unwrap(value)
      value.is_a?(GLib::Variant).then do |variant|
        if variant
          value.value
        else
          value
        end
      end
    end

    def enum_module(key)
      KEYS.fetch(key.to_s).last.tap do |type|
        unless type.respond_to?(:from_nick)
          raise ArgumentError, "#{key} is not an enum key"
        end
      end
    end

    def notify(key)
      @watchers.fetch(key, []).each { |block| block.call(key) }
    end

    def default_path
      File.join(
        ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
        'ruby-snapshot',
        'settings.json',
      )
    end

    def read
      File.exist?(@path).then do |exists|
        if exists
          JSON.parse(File.read(@path)).slice(*DEFAULTS.keys)
        else
          {}
        end
      end
    rescue JSON::ParserError => e
      warn "Error parsing #{@path}: #{e.message}"
      {}
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(@values))
    end
end
