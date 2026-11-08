# frozen_string_literal: true

require 'adwaita'

require_relative 'i18n'

# QrScreenBin dims the viewfinder and cuts a rounded square out of the dimming
# to aim a code at, a port of src/widgets/qr_screen_bin.rs.
#
# Upstream is an AdwBin subclass overriding snapshot(). It inscribes a square in
# the area the video feed actually occupies, takes the middle three fifths of it
# as the cutout, masks the dimming layer with the inverted alpha of that
# rounded rectangle's border, strokes the rectangle white, and writes "Scan
# Code" underneath it in semibold 16pt.
#
# The Ruby bindings cannot override a widget's snapshot vfunc, so the mask is
# painted by a non-targetable drawing area overlaid on the child: the dimming
# is filled, then the rounded rectangle is cleared out of it with Cairo's CLEAR
# operator, which is the inverted-alpha mask upstream pushes. The border and
# the label are drawn on top, all of it inside a group so the fade animation
# can set the opacity of the lot at once.
#
# `enabled` is the property the camera page flips when it switches into or out
# of code-detection mode; `viewfinder` is the widget the aspect ratio comes
# from, as upstream's property of the same name is.
#
class QrScreenBin
  include Snapshot::I18n
  Snapshot::I18n.bind(self)

  BORDER_RADIUS = 32.0
  BORDER_WIDTH = 4.0
  BG_OPACITY = 0.5
  ANIMATION_DURATION = 500

  LABEL = N_('Scan Code')
  LABEL_SIZE = 16
  LABEL_MARGIN = 12.0

  EPSILON = Float::EPSILON

  def initialize(child = nil, viewfinder: nil, enabled: false)
    @child = child
    @viewfinder = viewfinder
    @enabled = enabled
  end

  attr_reader :child, :viewfinder, :enabled

  def build
    bin.tap do |root|
      root.child = overlay

      overlay.tap do |stack|
        stack.child = @child
        stack.add_overlay(mask_area)

        mask_area.set_draw_func { |_, context, width, height| draw(context, width, height) }
      end
    end
  end

  def child=(widget)
    @child = widget
    overlay.child = widget
  end

  def viewfinder=(widget)
    @viewfinder = widget
    mask_area.queue_draw
  end

  # Upstream's set_enabled: a changed value restarts the fade in whichever
  # direction the new value calls for.
  def enabled=(value)
    (@enabled == value).then do |unchanged|
      unless unchanged
        @enabled = value
        dim_animation.reset
        dim_animation.reverse = !value
        dim_animation.play
      end
    end
  end

  # Memoized widget methods

  def bin = @bin ||= Adwaita::Bin.new
  def overlay = @overlay ||= Gtk::Overlay.new

  def mask_area
    @mask_area ||= Gtk::DrawingArea.new.tap do |area|
      area.can_target = false
      area.can_focus = false
    end
  end

  def dim_animation
    @dim_animation ||= Adwaita::TimedAnimation.new(
      mask_area,
      0.0,
      1.0,
      ANIMATION_DURATION,
      Adwaita::CallbackAnimationTarget.new { mask_area.queue_draw },
    )
  end

  private

    def draw(context, width, height)
      opacity.then do |alpha|
        if alpha > EPSILON
          cutout(width, height).then do |x, y, length|
            context.push_group
            paint_mask(
              context,
              width,
              height,
              [x, y, length],
            )
            paint_border(context, [x, y, length])
            draw_text(context, width, y + length)
            context.pop_group_to_source
            context.paint(alpha)
          end
        end
      end
    end

    # The dimming, with the rounded rectangle cleared back out of it.
    def paint_mask(context, width, height, rect)
      context.set_source_rgba(
        0.0,
        0.0,
        0.0,
        BG_OPACITY,
      )
      context.rectangle(
        0,
        0,
        width,
        height,
      )
      context.fill

      context.save
      context.operator = Cairo::OPERATOR_CLEAR
      rounded_rectangle(context, rect)
      context.fill
      context.restore
    end

    def paint_border(context, rect)
      context.set_source_rgb(1.0, 1.0, 1.0)
      context.line_width = BORDER_WIDTH
      rounded_rectangle(context, rect)
      context.stroke
    end

    def rounded_rectangle(context, rect)
      rect.then do |x, y, length|
        context.rounded_rectangle(
          x,
          y,
          length,
          length,
          BORDER_RADIUS,
          BORDER_RADIUS,
        )
      end
    end

    # "Scan Code", centred under the cutout. Upstream builds a Pango layout on
    # the widget and appends it to the snapshot; the layout here is the same
    # one, shown through Cairo.
    def draw_text(context, width, bottom)
      label_layout.then do |layout|
        layout.text = _(LABEL)
        context.set_source_rgb(1.0, 1.0, 1.0)
        context.move_to((width - layout.pixel_size.first) / 2.0, bottom + LABEL_MARGIN)
        context.show_pango_layout(layout)
      end
    end

    def label_layout
      @label_layout ||= mask_area.create_pango_layout.tap do |layout|
        layout.font_description = Pango::FontDescription.new.tap do |description|
          description.weight = :semibold
          description.size = Pango::SCALE * LABEL_SIZE
        end
      end
    end

    def opacity = dim_animation.value

    # Upstream inscribes a square in the video feed's own rectangle, then takes
    # the middle three fifths of that square as the cutout.
    def cutout(width, height)
      inner_size(width, height).then do |inner_width, inner_height|
        [inner_width, inner_height].min.then do |square|
          [
            ((width - square) / 2.0) + (square / 5.0),
            ((height - square) / 2.0) + (square / 5.0),
            3.0 * square / 5.0,
          ]
        end
      end
    end

    # Upstream reads the ratio off its viewfinder property; before the stream is
    # up there is none, and the widget's own rectangle is used so the mask is
    # still square and still centred.
    def inner_size(width, height)
      aspect_ratio(width, height).then do |aspect|
        (height < width && aspect < width.to_f / height).then do |letterboxed|
          if letterboxed
            [height * aspect, height.to_f]
          else
            [width.to_f, width / aspect]
          end
        end
      end
    end

    def aspect_ratio(width, height)
      @viewfinder.then do |widget|
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
          1.0
        end
      end
    end
end
