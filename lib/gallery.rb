# frozen_string_literal: true

require 'adwaita'

require_relative 'utils'
require_relative 'sliding_view'
require_relative 'gallery_picture'
require_relative 'gallery_video'

# Gallery is the full-screen view of everything the camera has captured, a
# port of src/widgets/gallery.rs and data/resources/ui/gallery.ui: a
# SlidingView of the pictures and videos under Utils.pictures_dir /
# Utils.videos_dir, a header bar with a menu, and a control strip with
# previous/next buttons, the open-externally and delete actions, and the
# media controls a video slide binds in. The gallery.next/previous/open/
# copy/delete actions upstream installs on the widget class are installed
# here as a Gio::SimpleActionGroup under the "gallery" prefix (see
# #action_group) so the secondary-click menu's gallery.copy/gallery.delete
# items (Utils.gallery_item_menu) actually resolve to something.
#
# Upstream reads the two directories with gio's async enumerator. This port
# reads them with plain Ruby Dir/File calls instead, the way Utils already
# reads user-dirs.dirs and writes pictures out — nothing here needs gio's
# enumerator for what is, underneath, a `Dir.children` and a `File.stat`.
class Gallery
  ATTRIBUTES_GLOB = '*'

  def initialize
    @current_item = nil
    @on_item_added = []
    @on_item_removed = []
  end

  def build
    breakpoint_bin.tap do |root|
      root.width_request = 360
      root.height_request = 294
      root.add_css_class('gallery')
      root.add_breakpoint(mobile_breakpoint)
      root.insert_action_group('gallery', action_group)

      root.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = sliding_view.build
        view.add_bottom_bar(controls_box)

        header_bar.pack_end(menu_button)
      end

      sliding_view.connect_target_page_reached { on_target_page_reached }
      sliding_view.connect_current_page_notify { on_current_page_changed }

      load_items
    end
  end

  # Upstream's add_image / add_video: a freshly captured file goes to the
  # front of the sliding view and is announced immediately.
  def add_image(file) = add_item(file, true, true)

  def add_video(file) = add_item(file, true, false)

  # Upstream's open(): jumps to the newest item without animating, the way
  # win.toggle-gallery does when it first raises the gallery page.
  def open
    first = sliding_view.pages.first
    sliding_view.scroll_to_velocity(first, nil) if first
  end

  def items = sliding_view.pages

  # Window, GalleryButton and CameraControls each watch the gallery
  # independently — the enable/disable of win.toggle-gallery, the circular
  # thumbnail's fade-in, and the control row's placeholder swap are three
  # separate concerns, not one. A single `@on_item_added = block` slot here
  # used to mean whichever of the three called `connect_item_added` last
  # silently overwrote the other two, so only CameraControls's own update
  # ever ran — the gallery button's thumbnail never painted, and
  # win.toggle-gallery never went insensitive when the gallery emptied.
  def connect_item_added(&block) = @on_item_added << block

  def connect_item_removed(&block) = @on_item_removed << block

  def next_item
    page = sliding_view.next_page
    sliding_view.scroll_to(page) if page
  end

  def previous_item
    page = sliding_view.prev_page
    sliding_view.scroll_to(page) if page
  end

  # Upstream's open_with_system.
  def open_with_system(window)
    item = sliding_view.current_page
    return unless item

    Gtk::FileLauncher.new(item.file).launch(window, nil) do |launcher, result|
      launcher.launch_finish(result)
    rescue GLib::Error => e
      warn "Could not open with system handler: #{e.message}"
    end
  end

  # Upstream's copy(): the current item's file, as a Gio::File, onto the
  # clipboard. `clipboard` defaults to the root widget's own, so the
  # `gallery.copy` action (below) and a caller that already holds a
  # clipboard reference both work.
  def copy(clipboard = breakpoint_bin.clipboard)
    item = sliding_view.current_page
    return false unless item

    clipboard.set(item.file)
    true
  end

  # Upstream's delete(): removes the slide first (so the sliding view has
  # already moved on by the time the file disappears), then deletes the file.
  def delete
    item = sliding_view.current_page
    return nil unless item

    is_last = sliding_view.pages.first == item
    sliding_view.remove(item)
    item.file.delete
    load_neighbor_pages
    @on_item_removed.each { |block| block.call(self, is_last) }
    item
  end

  private

    def add_item(file, load, is_picture)
      item = is_picture ? GalleryPicture.new(file, load: load) : GalleryVideo.new(file, load: load)
      sliding_view.prepend(item)
      @on_item_added.each { |block| block.call(self, item) } if load
      item
    end

    def on_target_page_reached
      load_neighbor_pages

      update_navigation_actions
    end

    def on_current_page_changed
      old = @current_item
      @current_item = sliding_view.current_page

      old.pause if old.is_a?(GalleryVideo)

      update_tooltip_and_menu
      update_navigation_actions
      setup_media_controls
    end

    def update_tooltip_and_menu
      current = sliding_view.current_page
      return unless current

      open_external_button.tooltip_text = current.is_picture? ? 'Open in Image Viewer' : 'Open in Video Player'
      menu_button.menu_model = Utils.gallery_item_menu(current.is_picture?)
    end

    def update_navigation_actions
      prev_button.sensitive = !sliding_view.prev_page.nil?
      next_button.sensitive = !sliding_view.next_page.nil?
    end

    def setup_media_controls
      current = sliding_view.current_page
      if current.is_a?(GalleryVideo)
        media_controls.visible = true
        media_controls.media_stream = current.stream
      else
        media_controls.visible = false
        media_controls.media_stream = nil
      end
    end

    def load_neighbor_pages
      [
        sliding_view.current_page,
        sliding_view.next_page,
        sliding_view.next_next_page,
        sliding_view.prev_page,
      ].compact.each { |page| page.start_loading unless page.started_loading? }
    end

    # Upstream's load_items: every picture and video under the two capture
    # directories, oldest first, with only the newest one decoded eagerly.
    def load_items
      entries = media_entries(Utils.pictures_dir, true) + media_entries(Utils.videos_dir, false)
      entries.sort_by! { |(_file, stamp, _is_picture)| stamp }
      return if entries.empty?

      *rest, last = entries
      rest.each { |file, _stamp, is_picture| add_item(file, false, is_picture) }

      last_file, _stamp, last_is_picture = last
      add_item(last_file, true, last_is_picture)
    end

    def media_entries(dir, is_picture)
      Dir.children(dir).sort.filter_map do |name|
        path = File.join(dir, name)
        next unless File.file?(path)

        stat = File.stat(path)
        [Gio::File.new_for_path(path), stat.ctime.to_f, is_picture]
      end
    rescue SystemCallError => e
      warn "Could not load items from #{dir}: #{e.message}"
      []
    end

    # Upstream installs gallery.next/previous/open/copy/delete as widget-class
    # actions (src/widgets/gallery.rs's class_init); the house style can't
    # subclass a widget class, so this port follows qr_bottom_sheet.rb's
    # pattern instead: a Gio::SimpleActionGroup inserted on the root widget
    # under the "gallery" prefix. Utils.gallery_item_menu's Gio::Menu names
    # gallery.copy/gallery.delete, and without this group those menu items
    # resolved to nothing and silently did nothing when clicked.
    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(next_action)
        group.add_action(previous_action)
        group.add_action(open_action)
        group.add_action(copy_action)
        group.add_action(delete_action)
      end
    end

    def next_action
      Gio::SimpleAction.new('next').tap { |action| action.signal_connect('activate') { next_item } }
    end

    def previous_action
      Gio::SimpleAction.new('previous').tap { |action| action.signal_connect('activate') { previous_item } }
    end

    def open_action
      Gio::SimpleAction.new('open').tap { |action| action.signal_connect('activate') { open_with_system(breakpoint_bin.root) } }
    end

    def copy_action
      Gio::SimpleAction.new('copy').tap { |action| action.signal_connect('activate') { copy } }
    end

    def delete_action
      Gio::SimpleAction.new('delete').tap { |action| action.signal_connect('activate') { delete } }
    end

    # Memoized widget methods

    def breakpoint_bin = @breakpoint_bin ||= Adwaita::BreakpointBin.new

    def mobile_breakpoint
      @mobile_breakpoint ||= Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse('max-width: 500px')).tap do |bp|
        bp.add_setter(controls_box, 'orientation', GLib::Value.new(Gtk::Orientation.gtype, :vertical))
      end
    end

    def toolbar_view
      @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
        view.extend_content_to_top_edge = true
        view.extend_content_to_bottom_edge = true
      end
    end

    def header_bar = @header_bar ||= Adwaita::HeaderBar.new.tap { |bar| bar.show_title = false }

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = 'view-more-symbolic'
        button.tooltip_text = 'Gallery Menu'
        button.add_css_class('flat')
        button.add_css_class('circular')
      end
    end

    def sliding_view = @sliding_view ||= SlidingView.new

    def prev_button
      @prev_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'go-previous-symbolic'
        button.tooltip_text = 'Previous Image'
        button.valign = :center
        button.sensitive = false
        button.add_css_class('osd')
        button.add_css_class('circular')
        button.add_css_class('gallerycontrols')
        button.signal_connect('clicked') { previous_item }
      end
    end

    def next_button
      @next_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'go-next-symbolic'
        button.tooltip_text = 'Next Image'
        button.valign = :center
        button.sensitive = false
        button.add_css_class('osd')
        button.add_css_class('circular')
        button.add_css_class('gallerycontrols')
        button.signal_connect('clicked') { next_item }
      end
    end

    def open_external_button
      @open_external_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = 'external-link-symbolic'
        button.tooltip_text = 'Open in Image Viewer'
        button.valign = :center
        button.add_css_class('osd')
        button.add_css_class('gallerycontrols')
        button.add_css_class('circular')
        button.signal_connect('clicked') { open_with_system(button.root) }
      end
    end

    def media_controls
      @media_controls ||= Gtk::MediaControls.new.tap do |mc|
        mc.valign = :center
        mc.halign = :fill
        mc.hexpand = true
        mc.visible = false
        mc.add_css_class('videoplayercontrols')
        mc.add_css_class('osd')
      end
    end

    # Upstream lays this row out differently on desktop and mobile through
    # AdwMultiLayoutView; this port keeps the one row and lets the mobile
    # breakpoint flip it to vertical, which is the same controls in a column
    # rather than a second hand-built layout.
    def controls_box
      @controls_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
        box.margin_start = 18
        box.margin_end = 18
        box.margin_top = 18
        box.margin_bottom = 18
        box.append(prev_button)
        box.append(next_button)
        box.append(media_controls)
        box.append(open_external_button)
      end
    end
end
