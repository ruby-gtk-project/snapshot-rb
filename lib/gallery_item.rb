# frozen_string_literal: true

require 'adwaita'

require_relative 'utils'

# GalleryItem is the base of one slide in the gallery, a port of
# src/widgets/gallery_item.rs: it owns the file the slide was made from,
# whether that file is a picture or a video, a thumbnail texture, and the
# secondary-click context menu every slide puts up.
#
# Upstream is a GtkWidget subclass with a BinLayout, so the real GObject
# hierarchy (GalleryPicture/GalleryVideo < GalleryItem < Gtk::Widget) is what
# SlidingView parents directly. The Ruby bindings cannot subclass a widget
# this deeply and still get vfuncs and signals right, so GalleryItem here is
# a plain object (the house style's `CameraRow`/`FlashBin` shape) whose #build
# returns the Adwaita::Bin that is actually parented into the sliding view;
# GalleryPicture and GalleryVideo are subclasses of this Ruby class, not of a
# widget.
#
# #load_content is what distinguishes a picture from a video and is left to
# the two subclasses; everything else here — the file, the started/loaded
# flags, the thumbnail, the context menu — is shared exactly as upstream
# shares it on the common GalleryItem GObject.
class GalleryItem
  def initialize(file:, is_picture:, load: false)
    @file = file
    @is_picture = is_picture
    @load = load
    @started_loading = false
    @loaded = false
    @thumbnail = nil
    @item = nil
  end

  attr_reader :file, :thumbnail

  def is_picture? = @is_picture

  def started_loading? = @started_loading

  def loaded? = @loaded

  def build
    @built.then do |already|
      unless already
        @built = true
        bin.add_controller(context_gesture)
        start_loading if @load
      end
    end
    bin
  end

  # Upstream's GalleryItem::set_item: swaps in the widget the subclass loaded
  # (a Gtk::Picture or a VideoPlayer) as the bin's one child.
  def item=(widget)
    (@item == widget).then do |unchanged|
      unless unchanged
        @item = widget
        bin.child = widget
      end
    end
  end

  attr_reader :item

  # Upstream's GalleryItem::start_loading: synchronous here since nothing
  # else in this port runs an async scheduler. Errors are logged and leave
  # the slide without a thumbnail rather than raising into the caller.
  def start_loading
    @started_loading = true
    load_content
    @loaded = true
    @on_loaded&.call
  rescue StandardError => e
    warn "Could not load gallery item for #{basename}: #{e.message}"
  end

  # Upstream's "loaded" property is a GObject notify that GalleryButton binds
  # a glib::SignalGroup to; this plain Ruby object has no notify signals, so
  # a direct callback stands in for that one binding.
  def on_loaded(&block)
    @on_loaded = block
  end

  private

    def set_thumbnail(texture)
      @thumbnail = texture
    end

    def basename
      @file.respond_to?(:basename) ? @file.basename.to_s : @file.to_s
    end

    def bin = @bin ||= Adwaita::Bin.new.tap { |b| b.halign = :center }

    # Upstream's construct_popover: a secondary-click menu pointing at the
    # click location, or centred when the click came from the keyboard.
    def context_gesture
      @context_gesture ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.button = Gdk::BUTTON_SECONDARY
        gesture.signal_connect('released') do |_, _n_press, x, y|
          show_popover(x, y)
        end
      end
    end

    def popover
      @popover ||= Gtk::PopoverMenu.new.tap do |menu|
        menu.menu_model = Utils.gallery_item_menu(is_picture?)
        menu.has_arrow = false
        menu.halign = :start
        menu.set_parent(bin)
      end
    end

    def show_popover(x, y)
      popover.pointing_to = (x > -1.0 && y > -1.0) ? Gdk::Rectangle.new(x.to_i, y.to_i, 0, 0) : nil
      popover.popup
    end
end
