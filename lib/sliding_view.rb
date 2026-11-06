# frozen_string_literal: true

require 'adwaita'

# SlidingView pages horizontally through the gallery's items, a port of
# src/widgets/sliding_view.rs — upstream's own doc comment calls it "similar
# to AdwCarousel".
#
# Upstream is a from-scratch GtkWidget: its own BinLayout-free measure/
# size_allocate, its own AdwSwipeTracker, its own AdwSpringAnimation. That is
# exactly what Adwaita::Carousel already is, and upstream's comment says as
# much, so this port is the thin wrapper upstream's comment points at rather
# than a second implementation of paging and swipe-tracking: Carousel does
# the swiping, the spring-animated scrolling and the snap points, and this
# class keeps the GalleryItem <-> page-widget bookkeeping upstream's
# SlidingView also keeps (`pages`, `current_page`, `next_page`/`prev_page`).
class SlidingView
  def initialize
    @pages = []
    @on_target_page_reached = nil
    @on_current_page_changed = nil

    carousel.signal_connect('page-changed') { |_, index| on_page_changed(index) }
  end

  def build = carousel

  def append(item) = insert(item, @pages.length)

  def prepend(item) = insert(item, 0)

  def insert(item, pos)
    if pos > @pages.length
      warn "Invalid insert position #{pos} for sliding view"
    else
      @pages.insert(pos, item)
      carousel.insert(item.build, pos)
      scroll_to_velocity(item, nil) if @pages.length == 1
    end
  end

  def move_to(item, new_index)
    index_of(item).then do |index|
      if index
        carousel.reorder(item.build, new_index)
        @pages.delete_at(index)
        @pages.insert(new_index, item)
      else
        warn 'Page to move not found'
      end
    end
  end

  def remove(item)
    scroll_to(next_page || prev_page) if next_page || prev_page

    index_of(item).then do |index|
      if index
        @pages.delete_at(index)
        carousel.remove(item.build)
        clear if @pages.empty?
      else
        warn 'Trying to remove non-existent page'
      end
    end
  end

  def clear
    @pages.clear
    @current_page = nil
  end

  def pages = @pages.dup

  def current_page = @current_page

  def connect_target_page_reached(&block) = @on_target_page_reached = block

  def connect_current_page_notify(&block) = @on_current_page_changed = block

  def scroll_to(item) = scroll_to_velocity(item, true)

  def scroll_to_velocity(item, animate)
    index_of(item).then do |index|
      if index
        carousel.scroll_to(item.build, animate != false)
        set_current_page(item)
      else
        warn 'Page not in SlidingView'
      end
    end
  end

  def next_page
    current_index.then { |index| index && @pages[index + 1] }
  end

  def next_next_page
    current_index.then { |index| index && @pages[index + 2] }
  end

  def prev_page
    current_index.then { |index| index && @pages[index - 1] if index && index.positive? }
  end

  private

    def carousel = @carousel ||= Adwaita::Carousel.new

    def index_of(item) = @pages.index(item)

    def current_index = @current_page && index_of(@current_page)

    def set_current_page(item)
      return if @current_page == item

      @current_page = item
      @on_current_page_changed&.call(self)
    end

    def on_page_changed(index)
      page = @pages[index]
      set_current_page(page) if page
      @on_target_page_reached&.call(self)
    end
end
