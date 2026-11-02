# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts, a port of upstream's
# data/resources/ui/shortcuts.ui: an AdwShortcutsDialog with the General,
# Camera and Gallery sections and the twelve items they hold.
#
# Upstream gives most items an action name rather than an accelerator, so
# Libadwaita looks the accelerator up from the application's own accels and the
# dialog cannot drift from what the app actually binds. Items whose shortcut is
# not an action — the three that only move focus or switch mode — carry a
# literal accelerator, exactly as upstream does.
#
# The Ruby ShortcutsItem constructor advertises both (title, accelerator) and
# (title, action_name) but matches the first, so action items are built with an
# empty accelerator and then given their action name.
#
class ShortcutsDialog < Adwaita::ShortcutsDialog
  # section title => [[item title, accelerator or nil, action name or nil], ...]
  SECTIONS = {
    'General' => [
      ['Show Shortcuts', nil, 'app.shortcuts'],
      ['Main Menu', 'F10', nil],
      ['Open Preferences', nil, 'win.preferences'],
      ['Close Window', nil, 'window.close'],
      ['Quit', nil, 'app.quit'],
    ],
    'Camera'  => [
      ['Picture Mode', 'P', nil],
      ['Recording Mode', 'R', nil],
      ['Take Picture or Start Recording', nil, 'win.take-picture'],
      ['Show/Hide Composition Guidelines', 'C', nil],
    ],
    'Gallery' => [
      ['Open/Close Gallery', nil, 'win.toggle-gallery'],
      ['Next', 'Right', nil],
      ['Previous', 'Left', nil],
    ],
  }.freeze

  def build
    tap do |dialog|
      SECTIONS.each do |title, items|
        dialog.add(section(title, items))
      end
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |entry| section.add(item(*entry)) }
      end
    end

    def item(title, accelerator, action_name)
      Adwaita::ShortcutsItem.new(title, accelerator.to_s).tap do |shortcut|
        action_name.then do |action|
          if action
            shortcut.action_name = action
          end
        end
      end
    end
end
