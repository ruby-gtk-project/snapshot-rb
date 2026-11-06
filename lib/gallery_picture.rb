# frozen_string_literal: true

require 'gtk4'
require 'glycin'
require 'libglycin-gtk4'

require_relative 'gallery_item'

# GalleryPicture is one picture slide in the gallery, a port of
# src/widgets/gallery_picture.rs: it decodes its file with glycin and shows
# the decoded frame in a Gtk::Picture.
#
# Upstream decodes through glycin's own async Rust API
# (`glycin::Loader::load_future`/`next_frame_future`) and turns the decoded
# frame into a GdkTexture with `glycin_gtk4::frame_get_texture`. The gems this
# port binds against are the same two libraries read off their GObject
# Introspection typelibs — `glycin` (`Gly`) and `libglycin-gtk4` (`GlyGtk4`) —
# so the call sequence here is the same three calls, synchronous rather than
# future-based.
class GalleryPicture < GalleryItem
  def initialize(file, load: false)
    super(file: file, is_picture: true, load: load)
  end

  def load_content
    loader = Gly::Loader.new(file)
    image = loader.load
    frame = image.next_frame
    texture = GlyGtk4.frame_get_texture(frame)

    picture.paintable = texture
    self.item = picture
    set_thumbnail(texture)
  end

  private

    def picture = @picture ||= Gtk::Picture.new
end
