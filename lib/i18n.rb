# frozen_string_literal: true

require 'gettext'

# Snapshot::I18n wires this port into upstream's own message catalogue: the
# domain is upstream's `meson.project_name()` ("snapshot", not
# "snapshot-rb"), so the `.mo` files built from the `po/` directory imported
# unchanged from upstream — every `.po`, `LINGUAS`, byte for byte — are the
# ones every `_()`/`n_()` call below actually resolves against. See
# `.reports/translation-parity.md` for the key-set census this exists to
# close, and the translation-parity skill for the discipline (byte-identical
# msgids, never reworded, never interpolated into).
#
# `glib2` only wraps `bindtextdomain` for GTK's own strings; this app's own
# strings go through the `gettext` gem, which is pure Ruby and needs no
# system gettext tooling to read a `.mo` it already has.
#
# `GetText#bindtextdomain` binds per including class, not per process (see
# the skill's ruby-gettext reference), so every file that wants `_()` either
# `include`s this module (instance methods — most widgets) or calls
# `Snapshot::I18n.bind(self)` (module functions — `Utils`, `Enums`).
module Snapshot
  module I18n
    DOMAIN = 'snapshot'
    LOCALE_DIR = File.expand_path('../locale', __dir__)

    include GetText
    bindtextdomain(DOMAIN, path: LOCALE_DIR)

    # For a module whose translatable methods are `def self.x` rather than
    # instance methods (house style's "free functions" modules) — `extend`ing
    # this module does not inherit the `include`d binding above, so each one
    # binds again directly.
    def self.bind(mod)
      mod.extend(GetText)
      mod.bindtextdomain(DOMAIN, path: LOCALE_DIR)
    end
  end
end
