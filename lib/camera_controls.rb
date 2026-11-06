# frozen_string_literal: true

require 'adwaita'

require_relative 'enums'
require_relative 'camera_row'
require_relative 'shutter_button'
require_relative 'gallery_button'

# CameraControls is the bottom control row of the camera page — the camera
# chooser, the shutter and the gallery button — a port of
# src/widgets/camera_controls.rs and data/resources/ui/camera_controls.ui.
#
# Each side of the row is a Gtk::Stack rather than a widget that just hides:
# upstream swaps in an empty AdwBin so hiding the gallery button (before
# anything has been captured) or the camera chooser (with zero or one camera)
# does not collapse the row's centring, and this port keeps the same stacks
# for the same reason.
#
class CameraControls
  def initialize
    @layout = Enums::ControlsLayout.default
    @on_camera_switched = nil
  end

  attr_reader :layout

  def build
    box.tap do |root|
      root.append(gallery_button_stack)
      root.append(shutter_button.build)
      root.append(camera_menu_button_stack)

      root.signal_connect('notify::orientation') { update_margins }
    end
  end

  def orientation=(value)
    box.orientation = value
  end

  def orientation = box.orientation

  # Upstream's set_layout: DETECTING_CODES hides the shutter and the gallery
  # button, leaving only the camera chooser.
  def layout=(value)
    (@layout == value).then do |unchanged|
      unless unchanged
        @layout = value
        detecting = value == Enums::ControlsLayout::DETECTING_CODES
        shutter_button.button.visible = !detecting
        gallery_button_stack.visible = !detecting
      end
    end
  end

  def connect_camera_switched(&block) = @on_camera_switched = block

  # Upstream's set_selection: wires a popover + list view of cameras onto the
  # chooser button. There is no device provider feeding a real camera list in
  # this port (see camera.rb), but the wiring itself works with any
  # Gio::ListModel-backed Gtk::SingleSelection a caller gives it.
  def set_selection(selection)
    @selection = selection

    list_view = Gtk::ListView.new(selection, camera_row_factory)
    popover.child = list_view
    camera_menu_button.popover = popover

    selection.signal_connect('notify::selected-item') { popover.popdown }
  end

  def set_countdown(seconds) = shutter_button.countdown = seconds

  def start_countdown = shutter_button.start_countdown

  def stop_countdown = shutter_button.stop_countdown

  def shutter_mode = shutter_button.shutter_mode

  def shutter_mode=(mode)
    shutter_button.shutter_mode = mode
  end

  def set_gallery(gallery)
    gallery_button.set_gallery(gallery)
    gallery.connect_item_added { |g, _| update_gallery_button(g) }
    gallery.connect_item_removed { |g, _| update_gallery_button(g) }
    update_gallery_button(gallery)
  end

  # Upstream's update_visible_camera_button: no chooser for zero or one
  # camera, a plain switch button for exactly two, the full popover menu for
  # more.
  def update_visible_camera_button(n_cameras)
    case n_cameras
    when 0, 1
      camera_menu_button_stack.visible_child_name = 'fake-widget'
    when 2
      camera_menu_button_stack.visible_child = camera_switch_button
    else
      camera_menu_button_stack.visible_child = camera_menu_button
    end
  end

  # Memoized widget methods

  def box
    @box ||= Gtk::Box.new(:horizontal, 24).tap do |b|
      b.halign = :center
      b.valign = :center
    end
  end

  def shutter_button = @shutter_button ||= ShutterButton.new

  def gallery_button = @gallery_button ||= GalleryButton.new

  def gallery_button_stack
    @gallery_button_stack ||= Gtk::Stack.new.tap do |stack|
      stack.add_named(Adwaita::Bin.new, 'fake-gallery-button')
      stack.add_named(gallery_button.build, 'gallery-button')
      stack.visible_child_name = 'fake-gallery-button'
    end
  end

  def camera_menu_button
    @camera_menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.halign = :center
      button.valign = :center
      button.icon_name = 'pick-camera-alt2-symbolic'
      button.tooltip_text = 'Select Camera'
      button.add_css_class('camerabutton')
      button.add_css_class('circular')
    end
  end

  def camera_switch_button
    @camera_switch_button ||= Gtk::Button.new.tap do |button|
      button.valign = :center
      button.halign = :center
      button.icon_name = 'cameras-symbolic'
      button.tooltip_text = 'Switch Camera'
      button.add_css_class('camerabutton')
      button.add_css_class('circular')
      button.signal_connect('clicked') { @on_camera_switched&.call(self) }
    end
  end

  def camera_menu_button_stack
    @camera_menu_button_stack ||= Gtk::Stack.new.tap do |stack|
      stack.add_named(camera_menu_button, 'camera-menu-button')
      stack.add_named(camera_switch_button, 'camera-switch-button')
      stack.add_named(Adwaita::Bin.new, 'fake-widget')
      stack.visible_child_name = 'fake-widget'
    end
  end

  def popover = @popover ||= Gtk::Popover.new.tap { |p| p.add_css_class('menu') }

  private

    def camera_row_factory
      @camera_row_factory ||= Gtk::SignalListItemFactory.new.tap do |factory|
        factory.signal_connect('setup') do |_, item|
          item.child = CameraRow.new.build
        end

        factory.signal_connect('bind') do |_, item|
          row = CameraRow.for(item.child)
          camera = item.item
          row.item = camera
          row.selected = @selection.selected_item == camera

          @selection.signal_connect('notify::selected-item') do
            row.selected = @selection.selected_item == camera
          end
        end

        factory.signal_connect('teardown') do |_, item|
          CameraRow.unregister(item.child)
        end
      end
    end

    def update_gallery_button(gallery)
      if gallery.items.empty?
        gallery_button_stack.visible_child_name = 'fake-gallery-button'
      else
        gallery_button_stack.visible_child_name = 'gallery-button'
      end
    end

    # Upstream's connect_orientation_notify: horizontal margins when laid out
    # as a row, vertical margins when laid out as a column.
    def update_margins
      box.margin_start = 0
      box.margin_end = 0
      box.margin_top = 0
      box.margin_bottom = 0

      if box.orientation == :horizontal
        box.margin_start = 12
        box.margin_end = 12
      else
        box.margin_top = 12
        box.margin_bottom = 12
      end
    end
end
