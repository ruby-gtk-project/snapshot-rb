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

  def load_content
    video_player.set_file(file)
    self.item = video_player
    video_player.realize

    (texture = video_player.thumbnail).then { |t| set_thumbnail(t) if t }
  end

  private

    def video_player = @video_player ||= VideoPlayer.new
end
