# frozen_string_literal: true

require 'adwaita'

# CameraRow is one row of the camera chooser popover, ported from
# src/widgets/camera_row.rs: a box with the camera's display name and a
# checkmark that is only visible for the camera currently in use.
#
# Upstream is a GtkBox subclass the list factory instantiates; here the rows are
# plain objects and the factory keeps them in REGISTRY, keyed by the box it
# built, so the bind step can find the row object belonging to a list item's
# child again. That is the repeater pattern the house style uses for
# SignalListItemFactory rows.
#
class CameraRow
  SPACING = 6

  # box => CameraRow, so a factory's bind step can get back from the widget a
  # list item hands it to the object that knows how to fill it in. The
  # factory's teardown step drops the entry again.
  REGISTRY = {}

  def self.for(widget) = REGISTRY[widget]

  def self.register(widget, row)
    REGISTRY[widget] = row
  end

  def self.unregister(widget)
    REGISTRY.delete(widget)
  end

  def build
    box.tap do |row|
      row.append(label)
      row.append(checkmark)

      self.class.register(row, self)
    end
  end

  # The camera this row stands for: upstream's set_item.
  def item=(camera)
    @item = camera
    label.label = camera.display_name.to_s
  end

  attr_reader :item

  # Upstream's set_selected: the checkmark is the only thing that moves.
  def selected=(selected)
    checkmark.visible = selected
  end

  def selected? = checkmark.visible?

  # Memoized widget methods

  def box = @box ||= Gtk::Box.new(:horizontal, SPACING)
  def label = @label ||= Gtk::Label.new

  def checkmark
    @checkmark ||= Gtk::Image.new.tap do |image|
      image.icon_name = 'object-select-symbolic'
      image.visible = false
    end
  end
end
