# frozen_string_literal: true

require 'adwaita'

# Style carries the app's stylesheet, a verbatim port of upstream's
# data/resources/style.css.
#
# Upstream ships the sheet inside its gresource bundle and GTK picks it up from
# the application's resource base path. There is no gresource bundle here, so
# the rules live in a heredoc and are installed on the default display with a
# CSS provider at application-startup priority — the same priority the resource
# path's automatic sheet gets.
#
# The element selectors (`camera`, `gallery`, `headerbar`) match the CSS names
# the widgets set on themselves; the class selectors match the classes the
# widgets add. Both sides have to agree, so neither this file nor the classes
# the widgets add should change alone.
module Style
  # The CSS classes the port's widgets add, and so the ones these rules reach.
  APPLIED_CLASSES = %w[
    shutterbutton
    gallerybutton
    camerabutton
    controlsframe
    startcontrolsframe
    videoplayercontrols
    gallerycontrols
    recording-label
    mobile
    portrait
  ].freeze

  CSS = <<~CSS
    .shutterbutton,
    .gallerybutton {
      color: white;
      background-color: transparent;
      border-radius: 999px;
      padding: 0;
      outline-offset: 5px;
    }

    .shutterbutton:focus:focus-visible,
    .gallerybutton:focus:focus-visible {
      outline-offset: 1px;
    }

    .shutterbutton {
      min-height: 64px;
      min-width: 64px;
    }

    .gallerybutton,
    .camerabutton {
      min-height: 44px;
      min-width: 44px;
    }

    .shutterbutton:active,
    .gallerybutton:active {
      opacity: .97;
    }

    gallery {
      background-color: black;
    }

    .videoplayercontrols {
      margin-left: 18px;
      margin-right: 18px;
      padding: 6px;
      border-radius: 50px;
    }

    .videoplayercontrols button {
     border-radius: 999px;
    }

    .controlsframe {
      background: rgba(0, 0, 0, 0.45);
    }

    camera .controlsframe {
      padding: 12px;
    }

    camera:not(.mobile) .bottom.controlsframe {
      padding-left: 18px;
      padding-right: 24px;
    }

    camera:not(.mobile) .startcontrolsframe {
      background: none;
    }

    gallery headerbar {
      background: rgba(0, 0, 0, 0.45);
    }

    gallery .controlsframe {
      padding: 6px;
    }

    gallery button.back {
      border-radius: 500px;
    }

    button.gallerycontrols.circular {
      padding: 9px;
      min-width: 24px;
      min-height: 24px;
    }

    camera .recording-label {
      padding: 12px 24px;
      border-radius: 500px;
      margin-bottom: 100px;
    }

    camera.portrait .recording-label {
      margin-bottom: 24px;
    }
  CSS

  # Installs the sheet on a display, the default one unless another is given.
  # Returns the provider so a caller that wants to take the sheet back off
  # again can.
  def self.load(display: Gdk::Display.default)
    provider.tap do |css|
      display.then do |target|
        if target
          Gtk::StyleContext.add_provider_for_display(
            target,
            css,
            Gtk::StyleProvider::PRIORITY_APPLICATION,
          )
        end
      end
    end
  end

  def self.provider
    @provider ||= Gtk::CssProvider.new.tap { |css| css.load(data: CSS) }
  end
end
