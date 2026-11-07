# frozen_string_literal: true

require_relative 'gallery_item'
require_relative 'video_player'

# GalleryVideo is one video slide in the gallery, a port of
# src/widgets/gallery_video.rs: it hands its file to a VideoPlayer and uses
# the player's own thumbnail snapshot as its thumbnail.
class GalleryVideo < GalleryItem
  def initialize(file, load: false)
    super(file: file, is_picture: false, load: load)
  end

  def stream = video_player.stream

  # Upstream's unmap(): a slide that scrolls off-screen stops playing rather
  # than running in the background.
  def pause = @video_player&.pause

  # Upstream's realize() is a GTK vfunc: GTK calls it itself, once, when the
  # widget actually gets mapped into a shown window. Calling it by hand here
  # used to mark the not-yet-parented video_player realized before GTK ever
  # attached it to the carousel; GTK then aborted the process with
  # `gtk_widget_root: assertion failed: (!priv->realized)` the moment the
  # slide was really inserted and GTK tried to realize it itself. set_file
  # already defers to VideoPlayer's own realize vfunc (see video_player.rb),
  # so nothing here needs to force it early — thumbnail() simply returns nil
  # until the stream has actually parsed a frame, the same as it always did.
  def load_content
    video_player.set_file(file)
    self.item = video_player

    (texture = video_player.thumbnail).then { |t| set_thumbnail(t) if t }
  end

  private

    def video_player = @video_player ||= VideoPlayer.new
end
