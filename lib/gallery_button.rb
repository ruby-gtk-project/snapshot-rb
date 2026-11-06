# frozen_string_literal: true

require 'adwaita'

# GalleryButton is the little circular thumbnail that opens the gallery, a
# port of src/widgets/gallery_button.rs: it shows the newest gallery item's
# thumbnail and fades a new one in when one arrives.
#
# Upstream overrides GtkWidget::snapshot() to grow the new thumbnail in from
# the centre over the previous one, clipped and bordered with hand-built GSK
# nodes. The Ruby bindings cannot override a widget's snapshot vfunc (see the
# ruby-gtk skill's quirks reference), and there is no safe binding here for
# blitting a raw GdkTexture through a Cairo::Context either, so this port
# shows the same thumbnail a different way: a Gtk::Picture set to the
# thumbnail's texture, clipped to the circle the `.gallerybutton` CSS class
# already cuts the button into (see style.rb), fading in over the same
# 250ms a TimedAnimation drives. What is lost is the previous thumbnail
# peeking out from behind the new one while it grows; what is kept is a
# circular thumbnail that appears instead of popping in.
class GalleryButton
  FADE_DURATION = 250

  def initialize
    @gallery = nil
  end

  def build
    button.tap do |btn|
      btn.child = picture
      btn.add_css_class('gallerybutton')
      btn.add_css_class('flat')
    end
  end

  # Upstream's set_gallery: watches item-added/item-removed so the drawn
  # thumbnail stays in step with the gallery, and the button only shows a
  # thumbnail once one has actually loaded.
  def set_gallery(gallery)
    @gallery = gallery

    gallery.connect_item_added do |_, item|
      if item.loaded?
        show_thumbnail(item.thumbnail)
      else
        item.on_loaded { show_thumbnail(item.thumbnail) }
      end
    end

    gallery.connect_item_removed do |_, is_last|
      show_thumbnail(gallery.items.first&.thumbnail) if is_last
    end
  end

  # Memoized widget methods

  def button = @button ||= Gtk::Button.new

  def picture
    @picture ||= Gtk::Picture.new.tap do |pic|
      pic.content_fit = :cover
      pic.can_shrink = true
      pic.opacity = 0.0
    end
  end

  def fade_animation
    @fade_animation ||= Adwaita::TimedAnimation.new(
      button,
      0.0,
      1.0,
      FADE_DURATION,
      Adwaita::CallbackAnimationTarget.new { |value| picture.opacity = value },
    )
  end

  private

    def show_thumbnail(texture)
      picture.paintable = texture
      texture ? fade_animation.play : (picture.opacity = 0.0)
    end
end
