# frozen_string_literal: true

require 'adwaita'

require_relative 'enums'
require_relative 'flash_bin'
require_relative 'guidelines_bin'
require_relative 'qr_screen_bin'
require_relative 'qr_bottom_sheet'
require_relative 'camera_controls'

# Camera is the camera page's own widget, a port of src/widgets/camera.rs and
# data/resources/ui/camera.ui: the viewfinder area wrapped in the flash,
# guidelines and QR-scan overlay bins, the recording-duration label, the
# bottom sheet a detected code raises, and the three breakpoints that switch
# the control row between a single horizontal bar, a vertical bar and a
# bottom bar depending on how much room the window has.
#
# Upstream's viewfinder comes from `aperture`, a GStreamer camera pipeline
# with no Ruby binding; the gems this port does bind against (glycin,
# libglycin-gtk4, gstreamer_pbutils) are decoders and a version-info reader,
# not a device provider, and do not fill that gap. So where
# upstream's viewfinder shows a live feed, this port shows the same
# "No Camera Found" status page Application showed before this file existed
# — now owned by Camera, alongside the controls that upstream always shows
# regardless of viewfinder state.
class Camera
  def initialize(settings:, on_toast: nil)
    @settings = settings
    @on_toast = on_toast
    @capture_mode = Enums::CaptureMode.default
    @recording_active = false
    @recording_seconds = 0
  end

  attr_reader :capture_mode

  def build
    breakpoint_bin.tap do |root|
      root.width_request = 360
      root.height_request = 294
      root.add_css_class('camera')
      root.add_css_class('portrait')
      root.add_breakpoint(single_landscape_bp)
      root.add_breakpoint(dual_portrait_bp)
      root.add_breakpoint(dual_landscape_bp)

      root.child = bottom_sheet

      toolbar_view.tap do |view|
        view.content = viewfinder_overlay
        view.add_bottom_bar(camera_controls.build)
      end

      viewfinder_overlay.tap do |overlay|
        overlay.child = flash_bin.build
        flash_bin.child = guidelines_bin.build
        guidelines_bin.child = qr_screen_bin.build
        qr_screen_bin.child = status_stack
        overlay.add_overlay(recording_revealer)
      end

      @settings.connect_changed('show-composition-guidelines') do
        guidelines_bin.draw_guidelines = @settings.show_composition_guidelines?
      end
    end
  end

  def set_capture_mode(mode)
    (@capture_mode == mode).then do |unchanged|
      unless unchanged
        @capture_mode = mode
        set_shutter_mode(mode == Enums::CaptureMode::VIDEO ? Enums::ShutterMode::VIDEO : Enums::ShutterMode::PICTURE)
        set_detect_codes(mode == Enums::CaptureMode::QR_DETECTION)
      end
    end
  end

  def set_countdown(seconds) = camera_controls.set_countdown(seconds)

  def start_countdown = camera_controls.start_countdown

  def stop_countdown = camera_controls.stop_countdown

  def shutter_mode = camera_controls.shutter_mode

  def set_shutter_mode(mode)
    stop_recording if mode == Enums::ShutterMode::PICTURE
    camera_controls.shutter_mode = mode
  end

  def set_gallery(gallery)
    camera_controls.set_gallery(gallery)
  end

  def toggle_guidelines
    guidelines_bin.toggle
    @settings.set_boolean('show-composition-guidelines', guidelines_bin.draw_guidelines)
  end

  def is_recording_active? = @recording_active

  # There is no viewfinder behind this port's camera page (see the class
  # comment), so every capture fails the way upstream's own camera-not-found
  # path does; the toast text matches what upstream's window.rs sends for
  # each capture mode.
  def take_picture(_format)
    @on_toast&.call('Could not take picture')
    false
  end

  def start_recording
    @on_toast&.call('Could not record video')
    false
  end

  def stop_recording
    return unless @recording_active

    @recording_active = false
    set_shutter_mode(Enums::ShutterMode::VIDEO)
    hide_recording_label
  end

  # No stream exists to start or stop; kept so Window can call these exactly
  # as it calls the upstream Camera's.
  def start_stream = nil

  def stop_stream = nil

  def set_page_visible(_visible) = nil

  private

    def set_detect_codes(detect)
      qr_screen_bin.enabled = detect
      camera_controls.layout = detect ? Enums::ControlsLayout::DETECTING_CODES : Enums::ControlsLayout::DEFAULT
    end

    def hide_recording_label
      @recording_seconds = 0
      recording_label.label = '0∶00'
      recording_revealer.reveal_child = false
    end

    # Memoized widget methods

    def breakpoint_bin = @breakpoint_bin ||= Adwaita::BreakpointBin.new

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

    def viewfinder_overlay = @viewfinder_overlay ||= Gtk::Overlay.new

    def flash_bin = @flash_bin ||= FlashBin.new

    def guidelines_bin
      @guidelines_bin ||= GuidelinesBin.new(draw_guidelines: @settings.show_composition_guidelines?)
    end

    def qr_screen_bin = @qr_screen_bin ||= QrScreenBin.new

    def status_stack
      @status_stack ||= Gtk::Stack.new.tap { |stack| stack.add_named(status_page, 'not-found') }
    end

    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = 'No Camera Found'
        page.description = 'Connect a camera to take pictures and videos'
        page.icon_name = 'camera-photo-symbolic'
      end
    end

    def recording_label
      @recording_label ||= Gtk::Label.new('0∶00').tap { |label| label.add_css_class('recording-label') }
    end

    def recording_revealer
      @recording_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.child = recording_label
        revealer.valign = :end
        revealer.halign = :center
        revealer.reveal_child = false
      end
    end

    def camera_controls = @camera_controls ||= CameraControls.new

    def qr_bottom_sheet = @qr_bottom_sheet ||= QrBottomSheet.new(on_toast: @on_toast)

    def bottom_sheet
      @bottom_sheet ||= Adwaita::BottomSheet.new.tap do |sheet|
        sheet.content = toolbar_view
        sheet.sheet = qr_bottom_sheet.build
      end
    end

    # Upstream's three AdwBreakpoints: single_landscape_bp lays the controls
    # out in one horizontal bar, dual_portrait_bp stacks them in a vertical
    # bar, and dual_landscape_bp is the narrow-but-short case, also
    # horizontal. All three mark the page "mobile" except the first.
    def single_landscape_bp
      @single_landscape_bp ||= breakpoint('max-aspect-ratio: 4/3 or max-height: 600') do
        breakpoint_bin.remove_css_class('mobile')
        camera_controls.orientation = :horizontal
      end
    end

    def dual_portrait_bp
      @dual_portrait_bp ||= breakpoint('max-height: 400') do
        breakpoint_bin.add_css_class('mobile')
        camera_controls.orientation = :vertical
      end
    end

    def dual_landscape_bp
      @dual_landscape_bp ||= breakpoint('max-aspect-ratio: 4/3 and max-width: 500') do
        breakpoint_bin.add_css_class('mobile')
        camera_controls.orientation = :horizontal
      end
    end

    def breakpoint(condition_string, &block)
      Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse(condition_string)).tap do |bp|
        bp.signal_connect('apply') { block.call }
      end
    end
end
