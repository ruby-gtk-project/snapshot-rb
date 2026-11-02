# frozen_string_literal: true

require 'fileutils'
require 'adwaita'

require_relative 'enums'

# Utils holds the free functions of upstream's src/utils.rs: the names new
# pictures and recordings are saved under, the two directories they are saved
# in, the debug dump the about dialog shows, and the context menu a gallery
# item puts up.
#
# Two things differ from upstream. The timestamps come from Ruby's Time rather
# than GLib::DateTime, which the Ruby bindings do not expose a now_local on,
# with the same format string and the same microsecond field. And the media
# directories come from the XDG user-dirs file rather than
# glib::user_special_dir, which the bindings do not expose either; the lookup
# order (environment variable, user-dirs.dirs, English fallback) is the one
# xdg-user-dir itself uses.
module Utils
  DATE_FORMAT = '%Y-%m-%d %H-%M-%S.%6N'

  # The subdirectory of the XDG pictures/videos directories both kinds of
  # capture are saved into. Upstream deliberately leaves it untranslated so
  # that switching locale does not move the user's files.
  CAMERA_SUBDIR = 'Camera'

  # The extensions of aperture's VideoFormat (aperture/src/enums.rs), which
  # upstream reads through VideoFormat::extension_as_str.
  VIDEO_EXTENSIONS = {
    vp8webm: 'webm',
    h264mp4: 'mp4',
  }.freeze

  # "Photo from 2023-05-21 11-05-59.123456.jpeg", or "Photo 12345.jpeg" if the
  # clock cannot be read.
  def self.picture_file_name(picture_format = Enums::PictureFormat.default)
    "#{timestamped_name('Photo from %<date>s', 'Photo %<number>d')}." \
      "#{Enums::PictureFormat.as_str(picture_format)}"
  end

  # "Recording from 2023-05-21 11-05-59.123456.webm", or "Recording 12345.webm".
  def self.video_file_name(video_format = :vp8webm)
    "#{timestamped_name('Recording from %<date>s', 'Recording %<number>d')}." \
      "#{VIDEO_EXTENSIONS.fetch(video_format, VIDEO_EXTENSIONS.fetch(:vp8webm))}"
  end

  def self.pictures_dir = media_dir('PICTURES', 'Pictures')

  def self.videos_dir = media_dir('VIDEOS', 'Videos')

  # The dump the about dialog's "Troubleshooting" page shows. Upstream lists
  # the versions of aperture, GStreamer, Pipewire and GTK, then every camera
  # the device provider found. There is no GStreamer binding for Ruby, so the
  # versions listed are the ones this port actually runs on; the camera
  # section, like upstream's, is left out entirely when no camera was found.
  def self.debug_info(cameras: [])
    "Library Details:\n\n#{library_details}".then do |details|
      cameras.empty?.then do |no_cameras|
        if no_cameras
          details
        else
          "#{details}\n\nCameras:\n\n#{cameras.map { |camera| camera_details(camera) }.join(",\n")}"
        end
      end
    end
  end

  def self.library_details
    [
      "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})",
      "Gtk #{Gtk::Version::MAJOR}.#{Gtk::Version::MINOR}.#{Gtk::Version::MICRO}",
      "Adwaita #{Adwaita::MAJOR_VERSION}.#{Adwaita::MINOR_VERSION}.#{Adwaita::MICRO_VERSION}",
      "gtk4 gem #{Gem.loaded_specs['gtk4']&.version || 'UNKNOWN'}",
      "adwaita gem #{Gem.loaded_specs['adwaita']&.version || 'UNKNOWN'}",
    ].join("\n")
  end

  # Upstream prints the camera's display name, its GStreamer device class and
  # its device properties; a camera here is anything that answers the same
  # three questions.
  def self.camera_details(camera)
    [
      camera.display_name,
      camera.respond_to?(:device_class) ? camera.device_class : 'camera',
    ].join(' ').then do |heading|
      "#{heading}: #{camera.respond_to?(:properties) ? camera.properties : {}}"
    end
  end

  # The secondary-click menu of a gallery page: upstream's gallery_item_menu.
  def self.gallery_item_menu(is_picture)
    Gio::Menu.new.tap do |menu|
      is_picture.then do |picture|
        if picture
          menu.append('_Copy Picture', 'gallery.copy')
        else
          menu.append('_Copy Video', 'gallery.copy')
        end
      end

      menu.append('_Delete', 'gallery.delete')
      menu.freeze
    end
  end

  # Both file-name helpers have the same shape: a timestamp if the clock can be
  # read, otherwise a random number in the range upstream uses.
  def self.timestamped_name(dated, numbered)
    format(dated, date: Time.now.strftime(DATE_FORMAT))
  rescue StandardError => e
    warn "Could not read the clock: #{e.message}"
    format(numbered, number: rand(0...999_999))
  end

  # The XDG directory for a kind of media, with the Camera subdirectory
  # created inside it.
  def self.media_dir(xdg_key, english_name)
    File.join(user_special_dir(xdg_key, english_name), CAMERA_SUBDIR).tap do |path|
      FileUtils.mkdir_p(path)
    end
  end

  def self.user_special_dir(xdg_key, english_name)
    ENV.fetch("XDG_#{xdg_key}_DIR", nil).then do |from_env|
      from_env || user_dirs.fetch(xdg_key, File.expand_path("~/#{english_name}"))
    end
  end

  # ~/.config/user-dirs.dirs is a shell fragment of
  # XDG_PICTURES_DIR="$HOME/Pictures" assignments.
  def self.user_dirs
    @user_dirs ||= read_user_dirs
  end

  def self.read_user_dirs
    File.join(
      ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
      'user-dirs.dirs',
    ).then do |path|
      File.exist?(path).then do |exists|
        if exists
          parse_user_dirs(File.read(path))
        else
          {}
        end
      end
    end
  rescue SystemCallError => e
    warn "Could not read user-dirs.dirs: #{e.message}"
    {}
  end

  def self.parse_user_dirs(contents)
    contents.scan(/^\s*XDG_(\w+)_DIR\s*=\s*"([^"]*)"/).to_h do |key, value|
      [key, value.gsub('$HOME', Dir.home)]
    end
  end
end
