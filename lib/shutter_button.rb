# frozen_string_literal: true

require 'adwaita'

require_relative 'enums'

# ShutterButton is the big round button in the middle of the control row, a
# port of src/widgets/shutter_button.rs.
#
# Upstream is a GtkButton subclass that draws itself in snapshot() and runs five
# animations at once: a press animation widening the gap between the ring and
# the inner shape, a hover animation scaling the whole button up by 5%, a mode
# animation fading the inner shape from white to red, a record animation turning
# the inner circle into a rotated rounded square, and a countdown animation
# emptying the ring like a clock face.
#
# The Ruby bindings cannot override a widget's snapshot vfunc, so the button
# holds a drawing area and paints there. Two things follow from using Cairo
# rather than GSK. The ring upstream masks with a conic gradient is drawn here
# as a stroked arc of the same sweep, starting at twelve o'clock and running
# clockwise — the same clock face, without the mask-and-render-to-texture dance
# upstream needs to work around a GTK bug. And the inner shape is a rounded
# rectangle filled directly rather than a clip filled with a larger rect.
#
# Everything else — the five animations, their durations and easings, the
# geometry, the colours, and the three tooltips — is upstream's.
#
class ShutterButton
  # Magic factor from upstream: inscribe a circle in a square of width w, then
  # a square in that circle; LAMBDA·w is the distance between the two squares,
  # which is the translation the record animation needs. (sqrt(2) - 1) / 2.
  LAMBDA = 0.20710677

  HOVER_SCALE = 1.05
  HOVER_DURATION = 125
  PRESS_DURATION = 125
  MODE_DURATION = 250
  COUNTDOWN_DURATION = 250
  RECORD_DURATION = 250

  PRESS_GAP_FROM = 4.0
  PRESS_GAP_TO = 8.0

  # Red 3 from the GNOME palette, the colour of a running recording.
  RECORDING_COLOR = [0.8784314, 0.14117648, 0.105882354].freeze

  # The tooltip for each shutter mode, upstream's set_shutter_mode.
  TOOLTIPS = {
    Enums::ShutterMode::PICTURE   => 'Take Picture',
    Enums::ShutterMode::VIDEO     => 'Start Recording',
    Enums::ShutterMode::RECORDING => 'Stop Recording',
  }.freeze

  # Where the mode and record animations end up for each mode: the mode
  # animation is 1 for anything video-ish, the record animation only for a
  # recording actually under way.
  MODE_TARGETS = {
    Enums::ShutterMode::PICTURE   => [0.0, 0.0],
    Enums::ShutterMode::VIDEO     => [1.0, 0.0],
    Enums::ShutterMode::RECORDING => [1.0, 1.0],
  }.freeze

  def initialize
    @shutter_mode = Enums::ShutterMode.default
    @countdown = 0
  end

  attr_reader :shutter_mode, :countdown

  def build
    button.tap do |root|
      root.child = drawing_area

      drawing_area.set_draw_func { |_, context, width, height| draw(context, width, height) }

      root.signal_connect('state-flags-changed') do |_, old_flags|
        on_state_flags_changed(old_flags)
      end
    end
  end

  # Upstream's countdown property: how many seconds the ring has to empty in.
  def countdown=(seconds)
    @countdown = seconds.to_i
  end

  # Upstream's set_shutter_mode: a changed mode retargets the mode and record
  # animations from wherever they currently are, plays both, and swaps the
  # tooltip.
  def shutter_mode=(mode)
    (@shutter_mode == mode).then do |unchanged|
      unless unchanged
        @shutter_mode = mode
        retarget(mode_animation, MODE_TARGETS.fetch(mode).first)
        retarget(record_animation, MODE_TARGETS.fetch(mode).last)
        button.tooltip_text = TOOLTIPS.fetch(mode)
      end
    end
  end

  # Upstream's start_countdown / stop_countdown. The ring starts full and
  # empties over the countdown's own length; stopping refills it at once.
  def start_countdown
    countdown_animation.value_to = 0.0
    countdown_animation.duration = @countdown * 1000
    countdown_animation.play
  end

  def stop_countdown
    countdown_animation.value_to = 1.0
    countdown_animation.duration = 0
    countdown_animation.play
  end

  # Memoized widget methods

  def button
    @button ||= Gtk::Button.new.tap do |widget|
      widget.add_css_class('shutterbutton')
      widget.add_css_class('flat')
      widget.tooltip_text = TOOLTIPS.fetch(Enums::ShutterMode.default)
    end
  end

  def drawing_area
    @drawing_area ||= Gtk::DrawingArea.new.tap do |area|
      area.can_target = false
      area.can_focus = false
    end
  end

  def press_animation
    @press_animation ||= timed_animation(PRESS_GAP_FROM, PRESS_GAP_TO, PRESS_DURATION)
  end

  def hover_animation
    @hover_animation ||= timed_animation(1.0, HOVER_SCALE, HOVER_DURATION)
  end

  def mode_animation
    @mode_animation ||= timed_animation(0.0, 1.0, MODE_DURATION)
  end

  def record_animation
    @record_animation ||= timed_animation(0.0, 0.0, RECORD_DURATION)
  end

  # Linear, and deaf to the "enable animations" setting: it is a clock, not a
  # flourish, so it has to run even where animations are switched off.
  def countdown_animation
    @countdown_animation ||= timed_animation(1.0, 0.0, COUNTDOWN_DURATION).tap do |animation|
      animation.easing = :linear
      animation.follow_enable_animations_setting = false
    end
  end

  private

    def timed_animation(from, to, duration)
      Adwaita::TimedAnimation.new(
        drawing_area,
        from,
        to,
        duration,
        Adwaita::CallbackAnimationTarget.new { drawing_area.queue_draw },
      )
    end

    # Upstream re-anchors an animation at its current value before sending it
    # somewhere else, so a mode change mid-animation does not jump.
    def retarget(animation, target)
      animation.value.then do |current|
        animation.value_from = current
        animation.value_to = target
        animation.play
      end
    end

    # Upstream's state_flags_changed: the press animation follows ACTIVE and
    # the hover animation follows PRELIGHT, each re-anchored at its current
    # value so a fast mouse does not make it jump.
    def on_state_flags_changed(old_flags)
      entered?(old_flags, :active).then do |pressed|
        if pressed
          retarget(press_animation, PRESS_GAP_TO)
        end
      end
      left?(old_flags, :active).then do |released|
        if released
          retarget(press_animation, PRESS_GAP_FROM)
        end
      end
      entered?(old_flags, :prelight).then do |hovered|
        if hovered
          retarget(hover_animation, HOVER_SCALE)
        end
      end
      left?(old_flags, :prelight).then do |unhovered|
        if unhovered
          retarget(hover_animation, 1.0)
        end
      end
    end

    def entered?(old_flags, flag) = flag?(button.state_flags, flag) && !flag?(old_flags, flag)

    def left?(old_flags, flag) = !flag?(button.state_flags, flag) && flag?(old_flags, flag)

    def flag?(flags, flag) = Gtk::StateFlags.new(flags).nick.to_s.split('|').include?(flag.to_s)

    def draw(context, width, height)
      [width, height].min.to_f.then do |size|
        [size / 8.0, 4.0].min.then do |border_width|
          context.save
          apply_hover(context, size)
          draw_border(context, size, border_width)
          draw_play(context, size, border_width)
          context.restore
        end
      end
    end

    # Upstream scales the whole button about its centre, which it does by
    # translating back by half the growth first.
    def apply_hover(context, size)
      hover_animation.value.then do |scale|
        context.translate(-(scale - 1.0) * size / 2.0, -(scale - 1.0) * size / 2.0)
        context.scale(scale, scale)
      end
    end

    # The ring, emptied clockwise from twelve o'clock by the countdown.
    def draw_border(context, size, border_width)
      countdown_animation.value.then do |fraction|
        if fraction > 0.0
          set_color(context, color)
          context.line_width = border_width
          context.new_path
          context.arc(
            size / 2.0,
            size / 2.0,
            (size - border_width) / 2.0,
            -Math::PI / 2.0,
            (-Math::PI / 2.0) + (2.0 * Math::PI * fraction),
          )
          context.stroke
        end
      end
    end

    # The inner shape: a circle for a picture, a rotated rounded square for a
    # recording, fading between white and red as the mode animation runs.
    def draw_play(context, size, border_width)
      inner_gap.then do |gap|
        record_animation.value.then do |record|
          context.save
          context.translate(size / 2.0, size / 2.0)
          context.rotate(-Math::PI / 2.0 * record)
          fill_inner_shape(
            context,
            size,
            border_width,
            [gap, record],
          )
          context.restore
        end
      end
    end

    def fill_inner_shape(context, size, border_width, state)
      state.then do |gap, record|
        (size - (2.0 * gap) - (2.0 * border_width)).then do |initial_size|
          (gap + border_width + (initial_size * LAMBDA * record)).then do |inset|
            (size - (2.0 * inset)).then do |rect_size|
              set_color(context, inner_color)
              context.rounded_rectangle(
                inset - (size / 2.0),
                inset - (size / 2.0),
                rect_size,
                rect_size,
                (1.0 - (record * 0.7)) * rect_size / 2.0,
                (1.0 - (record * 0.7)) * rect_size / 2.0,
              )
              context.fill
            end
          end
        end
      end
    end

    # Upstream skips the press animation while the button is a square, where it
    # would fight the record animation and look janky — unless a countdown is
    # set, in which case the press is the only feedback there is.
    def inner_gap
      (@shutter_mode == Enums::ShutterMode::PICTURE || @countdown.positive?).then do |animated|
        if animated
          press_animation.value
        else
          PRESS_GAP_FROM
        end
      end
    end

    def inner_color
      mode_animation.value.then do |t|
        [
          lerp(t, color.red, RECORDING_COLOR[0]),
          lerp(t, color.green, RECORDING_COLOR[1]),
          lerp(t, color.blue, RECORDING_COLOR[2]),
          color.alpha,
        ]
      end
    end

    def lerp(t, from, to) = (to * t) + ((1.0 - t) * from)

    def set_color(context, rgba)
      rgba.is_a?(Array).then do |components|
        if components
          context.set_source_rgba(
            rgba[0],
            rgba[1],
            rgba[2],
            rgba[3],
          )
        else
          context.set_source_rgba(
            rgba.red,
            rgba.green,
            rgba.blue,
            rgba.alpha,
          )
        end
      end
    end

    # The CSS colour of the button, which style.css paints white.
    def color = button.color
end
