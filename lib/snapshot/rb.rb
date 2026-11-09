require_relative "rb/version"

# frozen_string_literal: true

# The gem's version constant lives under here, which is why
# spec/spec_helper.rb requires this file directly: the gemspec and the specs
# need nothing more than the version to load, and loading `snapshot` itself
# pulls in gtk4, which raises Gtk::InitError without a display.
