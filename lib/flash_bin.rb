# frozen_string_literal: true

require 'adwaita'

# FlashBin wraps the viewfinder and flashes it black when a picture is taken, a
# port of src/widgets/flash_bin.rs.
#
# Upstream is an AdwBin subclass that overrides snapshot() and appends a black
# rectangle over its child while the animation runs. The Ruby bindings cannot
# override a widget's snapshot vfunc, so the flash is painted by a
# non-targetable drawing area overlaid on the child instead — the same black
# rectangle, at the same alpha, driven by the same 250ms linear animation.
#
# The alpha curve is upstream's `easing`: a cubic ease-out fed into x(1-x)·4,
# which rises from nothing to 1 at the midpoint and falls back, so the flash
# fades in and straight back out again.
#
class FlashBin
  DURATION = 250

  def initialize(child = nil)
    @child = child
  end

  attr_reader :child

  def build
    bin.tap do |root|
      root.child = overlay

      overlay.tap do |stack|
        stack.child = @child
        stack.add_overlay(flash_area)

        flash_area.set_draw_func { |_, context, width, height| draw(context, width, height) }
      end
    end
  end

  # Upstream's child setter: the bin's child is the viewfinder, which the camera
  # page swaps in once the stream is up.
  def child=(widget)
    @child = widget
    overlay.child = widget
  end

  # Upstream's `flash`.
  def flash = flash_animation.play

  def flashing? = flash_animation.state == Adwaita::AnimationState::PLAYING

  # Memoized widget methods

  def bin = @bin ||= Adwaita::Bin.new
  def overlay = @overlay ||= Gtk::Overlay.new

  # can_target false so the flash never swallows a click meant for the
  # viewfinder underneath it.
  def flash_area
    @flash_area ||= Gtk::DrawingArea.new.tap do |area|
      area.can_target = false
      area.can_focus = false
    end
  end

  def flash_animation
    @flash_animation ||= Adwaita::TimedAnimation.new(
      flash_area,
      0.0,
      1.0,
      DURATION,
      Adwaita::CallbackAnimationTarget.new { flash_area.queue_draw },
    ).tap { |animation| animation.easing = :linear }
  end

  private

    def draw(context, width, height)
      flashing?.then do |running|
        if running
          context.set_source_rgba(
            0.0,
            0.0,
            0.0,
            easing(flash_animation.value),
          )
          context.rectangle(
            0,
            0,
            width,
            height,
          )
          context.fill
        end
      end
    end

    def easing(value)
      (1.0 - ((1.0 - value)**3)).then { |eased| eased * (1.0 - eased) * 4.0 }
    end
end
