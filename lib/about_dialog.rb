# frozen_string_literal: true

require 'adwaita'

require_relative 'utils'
require_relative 'i18n'

# AboutDialog is the dialog behind win.about, ported from
# Window::show_about_dialog in upstream's src/widgets/window.rs together with
# the metadata it reads out of
# data/resources/org.gnome.Snapshot.metainfo.xml.in.in.
#
# Upstream builds the dialog with AboutDialog::from_appdata, which reads the
# app's name, summary, licence, URLs and release notes back out of the
# metainfo file inside its gresource bundle, then adds the credits and the
# debug dump by hand. There is no gresource bundle here, so the same fields are
# set from the constants below — every one of them is the value the metainfo
# file carries — and the credits and debug dump are added exactly as upstream
# adds them.
#
class AboutDialog < Adwaita::AboutDialog
  include Snapshot::I18n
  Snapshot::I18n.bind(self)

  APPLICATION_NAME = N_('Camera')
  APPLICATION_ICON = 'org.gnome.Snapshot'
  DEVELOPER_NAME = N_('The GNOME Project')
  COMMENTS = N_('Take pictures and videos on your computer, tablet, or phone.')
  COPYRIGHT = '© 2023 The GNOME Project'

  WEBSITE = 'https://apps.gnome.org/Snapshot/'
  ISSUE_URL = 'https://gitlab.gnome.org/GNOME/snapshot/issues'
  SUPPORT_URL = 'https://matrix.to/#/#snapshot:gnome.org'

  DEVELOPERS = ['Maximiliano Sandoval', 'Jamie Murphy <jmurphy@gnome.org>'].freeze
  DESIGNERS = ['Tobias Bernard'].freeze

  # The notes of the newest release in the metainfo file.
  RELEASE_NOTES_VERSION = '51~beta'
  RELEASE_NOTES = <<~NOTES
    <p>Snapshot 51.beta release</p>
    <ul>
      <li>Inhibit idle while the viewfinder is active</li>
      <li>Updated translations</li>
    </ul>
  NOTES

  # cameras is what the device provider found, for the Troubleshooting page's
  # debug dump; upstream reads it off the provider singleton.
  def initialize(version:, cameras: [])
    super()
    @version = version
    @cameras = cameras
  end

  def build
    tap do |dialog|
      dialog.application_name = _(APPLICATION_NAME)
      dialog.application_icon = APPLICATION_ICON
      dialog.developer_name = _(DEVELOPER_NAME)
      dialog.comments = _(COMMENTS)
      dialog.copyright = COPYRIGHT
      dialog.license_type = Gtk::License::GPL_3_0

      dialog.website = WEBSITE
      dialog.issue_url = ISSUE_URL
      dialog.support_url = SUPPORT_URL

      # Upstream shows the release notes AboutDialog::from_appdata picked up
      # from the metainfo file.
      dialog.release_notes_version = RELEASE_NOTES_VERSION
      dialog.release_notes = RELEASE_NOTES

      # Upstream passes the version with any pre-release suffix stripped off.
      dialog.version = @version.to_s.split('-').first

      dialog.translator_credits = _('translator-credits')
      dialog.developers = DEVELOPERS
      dialog.designers = DESIGNERS
      dialog.debug_info = Utils.debug_info(cameras: @cameras)
    end
  end
end
