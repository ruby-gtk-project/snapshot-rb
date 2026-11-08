# frozen_string_literal: true

require 'gobject-introspection'

# ApertureUtils is a port of aperture's src/utils.rs `caps` module: the pure
# caps-filtering helpers the camera pipeline uses to decide what the camera
# can actually show (is this mode infrared, what's the best resolution, is
# the framerate within the app's cap). Nothing here touches a camera device;
# it is the subset of utils.rs that is plain GstCaps arithmetic and so is the
# only part of the aperture crate this port can honestly bring over without
# a Ruby GStreamer camera-device-provider binding.
#
# Upstream reaches `gst::Caps` through gstreamer-rs. No packaged Ruby gem
# wraps core GStreamer (`Gst::Caps` and friends) the way glycin,
# libglycin-gtk4 and gstreamer_pbutils wrap their own namespaces — the
# gstreamer_pbutils gem's own loader comment says as much: "Callers who want
# `Gst::Caps` install it themselves". This module is exactly that caller: it
# loads the `Gst-1.0` typelib straight off the GObject Introspection
# repository, the same mechanism gstreamer_pbutils's loader uses internally
# to run `gst_init_check`, rather than hand-rolling caps parsing or shelling
# out to `gst-launch`.
module ApertureUtils
  # Defines the small slice of the Gst namespace (Caps, Structure,
  # CapsIntersectMode) this module calls, straight from `Gst-1.0.typelib`.
  # Modelled on gstreamer_pbutils's own loader, which calls
  # `repository.require("Gst", "1.0")` and `Gst.init_check` for the exact
  # same reason: GStreamer's type system does not exist until core is
  # initialised.
  class GstLoader < GObjectIntrospection::Loader
    def load
      self.version = '1.0'
      super('Gst')
    end
  end

  def self.gst
    @gst ||= Module.new.tap do |mod|
      GstLoader.new(mod).load
      ok, = mod.init_check([$PROGRAM_NAME])
      raise 'gst_init_check failed: GStreamer core is unusable' unless ok
    end
  end

  SUPPORTED_ENCODINGS = ['video/x-raw', 'image/jpeg'].freeze
  PREFERRED_FORMATS = %w[I420 BGRx RGBx xBGR xRGB].freeze
  # The maximum framerate, in frames per second.
  MAXIMUM_RATE = 30

  # Supported caps for the app, already frame capped — aperture's
  # SUPPORTED_CAPS, built once from SUPPORTED_ENCODINGS with a
  # `framerate=[0/1, MAXIMUM_RATE/1]` range on each.
  def self.supported_caps
    @supported_caps ||= gst::Caps.from_string(
      SUPPORTED_ENCODINGS.map { |enc| "#{enc}, framerate=(fraction)[0/1, #{MAXIMUM_RATE}/1]" }.join(';'),
    )
  end

  # Infrared caps: each supported encoding, restricted to GRAY8 — aperture's
  # IR_CAPS.
  def self.ir_caps
    @ir_caps ||= gst::Caps.from_string(
      SUPPORTED_ENCODINGS.map { |enc| "#{enc}, format=GRAY8" }.join(';'),
    )
  end

  # aperture::utils::caps::is_infrared.
  def self.infrared?(cap)
    cap.subset?(ir_caps)
  end

  # aperture::utils::caps::limit_fps. Intersects with SUPPORTED_CAPS using
  # gst's "first" intersection mode (ZERO is GST_CAPS_INTERSECT_ZIG_ZAG,
  # ONE/first-field-wins is GST_CAPS_INTERSECT_FIRST, which is what upstream
  # passes).
  FIRST_MODE = 1

  def self.limit_fps(caps)
    caps.intersect_full(supported_caps, FIRST_MODE)
  end

  Size = Struct.new(:width, :height)

  # aperture::utils::caps::best_mode. Picks the best size among `caps`'
  # structures: prefers a 16:9-ish size within [640x480, max_width x 1080],
  # falls back to any size in that band, falls back to the first size seen
  # at all.
  def self.best_mode(caps)
    min_width = 640
    min_height = 480
    max_height = 1080
    optimal_ratio = 16.0 / 9.0

    best_optimal = nil
    best_any = nil
    best_fallback = nil

    caps.size.times do |i|
      structure = caps.get_structure(i)
      width = structure.get_value('width')&.value
      height = structure.get_value('height')&.value
      next unless width.is_a?(Integer) && height.is_a?(Integer)

      best_fallback ||= Size.new(width, height)

      max_width = (height * optimal_ratio).ceil
      next unless (min_width..max_width).cover?(width) && (min_height..max_height).cover?(height)

      if width == (height * optimal_ratio).to_i
        best_optimal = Size.new(width, height) if best_optimal.nil? || (width >= best_optimal.width && height >= best_optimal.height)
      elsif best_any.nil? || (width >= best_any.width && height >= best_any.height)
        best_any = Size.new(width, height)
      end
    end

    best_optimal || best_any || best_fallback
  end
end
