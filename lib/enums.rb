# frozen_string_literal: true

# Enums holds the four enumerations upstream declares in src/enums.rs:
# PictureFormat and CaptureMode (both also declared in the gschema, so they
# carry gschema nicks), ShutterMode and ControlsLayout (internal to the
# widgets).
#
# Upstream registers each one as a GLib enum so GSettings and GtkBuilder can
# name its members. The Ruby port has no .ui files and its settings are keyed
# by nick (see Settings), so the members are plain symbols and the numeric
# discriminants live in the ordering of ALL — the same order as the Rust
# variants, which is what `#[repr(u32)]` makes the on-disk values.
#
module Enums
  # Behaviour shared by the four enumerations: the numeric value of a member is
  # its index in ALL, the default member is the first (upstream marks the first
  # variant `#[default]` in every case), and the gschema nick is the member
  # name with underscores turned into dashes.
  module Enumeration
    def all = self::ALL

    def default = self::ALL.first

    # Upstream's `From<i32>` implementations fall back to the default member
    # for any value outside the enum, which is what fetch's default does here.
    def from_value(value) = by_value.fetch(value.to_i, default)

    def to_value(member) = by_value.key(member)

    def nick(member) = member.to_s.tr('_', '-')

    def from_nick(name)
      self::ALL.find { |member| nick(member) == name.to_s }.then do |member|
        member || default
      end
    end

    def by_value
      @by_value ||= self::ALL.each_with_index.to_h { |member, index| [index, member] }
    end
  end

  # The org.gnome.Snapshot.PictureFormat gschema enum. Upstream has had only
  # JPEG since the PNG support was dropped; its `From<i32>` maps 1 to Jpeg and
  # everything else to the default, which is Jpeg as well, so every value
  # arrives as :jpeg either way.
  module PictureFormat
    extend Enumeration

    JPEG = :jpeg
    ALL = [JPEG].freeze

    # The file-name extension, upstream's `as_str`.
    EXTENSIONS = { JPEG => 'jpeg' }.freeze

    # The name the preferences window shows, upstream's `translatable_string`.
    DISPLAY_NAMES = { JPEG => 'JPEG' }.freeze

    def self.as_str(member) = EXTENSIONS.fetch(member, EXTENSIONS.fetch(default))

    def self.translatable_string(member)
      DISPLAY_NAMES.fetch(member, DISPLAY_NAMES.fetch(default))
    end
  end

  # The org.gnome.Snapshot.CaptureMode gschema enum: what the shutter does.
  module CaptureMode
    extend Enumeration

    PICTURE = :picture
    VIDEO = :video
    QR_DETECTION = :qr_detection
    ALL = [PICTURE, VIDEO, QR_DETECTION].freeze
  end

  # How the shutter button draws itself. Not a gschema enum: the window derives
  # it from the capture mode and from whether a recording is running.
  module ShutterMode
    extend Enumeration

    PICTURE = :picture
    VIDEO = :video
    RECORDING = :recording
    ALL = [PICTURE, VIDEO, RECORDING].freeze
  end

  # Which controls the camera control row shows. DETECTING_CODES hides the
  # shutter and the gallery button, leaving only the camera chooser.
  module ControlsLayout
    extend Enumeration

    DEFAULT = :default
    DETECTING_CODES = :detecting_codes
    ALL = [DEFAULT, DETECTING_CODES].freeze
  end
end
