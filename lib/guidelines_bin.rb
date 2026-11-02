# frozen_string_literal: true

require 'adwaita'

# GuidelinesBin draws the rule-of-thirds grid over the viewfinder, a port of
# src/widgets/guidelines_bin.rs.
#
# Upstream is an AdwBin subclass overriding snapshot(): it asks its child for
# the viewfinder's aspect ratio, works out the rectangle the video feed
# actually occupies inside the widget, and paints two vertical and two
# horizontal lines at the thirds of that rectangle — each a 1px white line over
# a 3px black one, so the grid reads over a light scene as well as a dark one.
# The whole grid fades in and out over 250ms with an ease-in-quad curve.
#
# The Ruby bindings cannot override a widget's snapshot vfunc, so the grid is
# painted by a non-targetable drawing area overlaid on the child. The aspect
# ratio comes from the child when the child can report one, as upstream's does;
# when it cannot — before the stream is up — the widget's own aspect ratio is
# used, so the grid covers the whole area rather than disappearing.
#
# draw_guidelines is the property the camera page keeps bound to the
# show-composition-guidelines setting.
#
class GuidelinesBin
  DURATION = 250

  # The grid itself, and the shadow under it.
  LINE_COLOR = [1.0, 1.0, 1.0, 0.5].freeze
  SHADOW_COLOR = [0.0, 0.0, 0.0, 0.1].freeze
  LINE_WIDTH = 1.0
  SHADOW_WIDTH = 3.0

  EPSILON = Float::EPSILON

  def initialize(child = nil, draw_guidelines: false)
    @child = child
    @draw_guidelines = draw_guidelines
    @played_initial = false
  end

  attr_reader :child, :draw_guidelines

  def build
    bin.tap do |root|
      root.child = overlay

      overlay.tap do |stack|
        stack.child = @child
        stack.add_overlay(guidelines_area)

        guidelines_area.set_draw_func { |_, context, width, height| draw(context, width, height) }
      end
    end
  end

  def child=(widget)
    @child = widget
    overlay.child = widget
  end

  # Upstream's set_draw_guidelines: nothing happens unless the value actually
  # changed, and then the animation is restarted in whichever direction the new
  # value calls for.
  def draw_guidelines=(value)
    (@draw_guidelines == value).then do |unchanged|
      unless unchanged
        @draw_guidelines = value
        restart_animation
      end
    end
  end

  def toggle = self.draw_guidelines = !@draw_guidelines

  # Memoized widget methods

  def bin = @bin ||= Adwaita::Bin.new
  def overlay = @overlay ||= Gtk::Overlay.new

  def guidelines_area
    @guidelines_area ||= Gtk::DrawingArea.new.tap do |area|
      area.can_target = false
      area.can_focus = false
    end
  end

  def animation
    @animation ||= Adwaita::TimedAnimation.new(
      guidelines_area,
      0.0,
      1.0,
      DURATION,
      Adwaita::CallbackAnimationTarget.new { guidelines_area.queue_draw },
    ).tap { |timed| timed.easing = :ease_in_quad }
  end

  private

    def restart_animation
      animation.reset
      animation.reverse = !@draw_guidelines
      animation.play
    end

    # Upstream plays the animation on the first snapshot if the guidelines were
    # already switched on when the widget appeared, so that they fade in rather
    # than pop in.
    def play_initial
      @played_initial.then do |played|
        unless played
          @played_initial = true
          if @draw_guidelines
            animation.play
          end
        end
      end
    end

    def draw(context, width, height)
      play_initial

      aspect_ratio(width, height).then do |aspect|
        if aspect > EPSILON
          draw_grid(
            context,
            width,
            height,
            aspect,
          )
        end
      end
    end

    def draw_grid(context, width, height, aspect)
      alpha.then do |opacity|
        if opacity.abs > EPSILON
          inner_size(width, height, aspect).then do |inner_width, inner_height|
            context.save
            context.translate((width - inner_width) / 2.0, (height - inner_height) / 2.0)
            paint_lines(
              context,
              inner_width,
              inner_height,
              opacity,
            )
            context.restore
          end
        end
      end
    end

    def paint_lines(context, width, height, opacity)
      (width / 3.0).round.then do |third_x|
        (height / 3.0).round.then do |third_y|
          paint_pass(
            context,
            SHADOW_COLOR,
            SHADOW_WIDTH,
            opacity,
            third_x,
            third_y,
            width,
            height,
          )
          paint_pass(
            context,
            LINE_COLOR,
            LINE_WIDTH,
            opacity,
            third_x,
            third_y,
            width,
            height,
          )
        end
      end
    end

    # One pass of the grid: the two vertical lines then the two horizontal
    # ones. The shadow pass is 3px wide and offset back by a pixel, exactly as
    # upstream's rectangles are.
    def paint_pass(context, color, thickness, opacity, third_x, third_y, width, height)
      context.set_source_rgba(
        color[0],
        color[1],
        color[2],
        color[3] * opacity,
      )
      ((thickness - LINE_WIDTH) / 2.0).then do |offset|
        [third_x, 2 * third_x].each do |x|
          context.rectangle(
            x - offset,
            0,
            thickness,
            height,
          )
        end
        [third_y, 2 * third_y].each do |y|
          context.rectangle(
            0,
            y - offset,
            width,
            thickness,
          )
        end
      end
      context.fill
    end

    # Upstream's alpha: while the animation runs its current value, and once it
    # has settled whichever end of the animation the property calls for.
    def alpha
      (animation.state == Adwaita::AnimationState::PLAYING).then do |playing|
        if playing
          animation.value
        else
          settled_alpha
        end
      end
    end

    def settled_alpha
      @draw_guidelines.then do |showing|
        if showing
          animation.value_to
        else
          animation.value_from
        end
      end
    end

    # Upstream reads the ratio off the aperture viewfinder it expects as its
    # child; anything that can report one does here.
    def aspect_ratio(width, height)
      @child.then do |widget|
        if widget.respond_to?(:aspect_ratio) && widget.aspect_ratio.to_f > EPSILON
          widget.aspect_ratio.to_f
        else
          own_aspect_ratio(width, height)
        end
      end
    end

    def own_aspect_ratio(width, height)
      (height.to_f > EPSILON).then do |measurable|
        if measurable
          width / height.to_f
        else
          0.0
        end
      end
    end

    # Upstream's calculate_aspect_ratio: the largest rectangle of the given
    # ratio that fits inside the widget.
    def inner_size(width, height, aspect)
      (height < width && aspect < width.to_f / height).then do |letterboxed|
        if letterboxed
          [height * aspect, height.to_f]
        else
          [width.to_f, width / aspect]
        end
      end
    end
end
