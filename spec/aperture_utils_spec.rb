# frozen_string_literal: true

require 'aperture_utils'

# Port of aperture/src/utils.rs's `mod tests` — test_is_infrared,
# test_limit_fps and test_best_height — against ApertureUtils, which ports
# the `caps` module those tests exercise.
RSpec.describe ApertureUtils do
  let(:gst) { described_class.gst }

  describe '.infrared?' do
    it 'is true for caps that are a subset of the infrared caps' do
      infrared_caps = [
        gst::Caps.from_string('image/jpeg,format=GRAY8'),
        gst::Caps.from_string('video/x-raw,format=GRAY8'),
        gst::Caps.from_string('image/jpeg,format=GRAY8;video/x-raw,format=GRAY8'),
      ]

      infrared_caps.each do |cap|
        expect(described_class.infrared?(cap)).to be(true)
      end
    end

    it 'is false for caps that are not a subset of the infrared caps' do
      not_infrared_caps = [
        gst::Caps.from_string('video/x-raw,format=GRAY8;video/x-raw,format=YV12'),
        gst::Caps.from_string('video/x-raw,format=YV12'),
        gst::Caps.from_string('video/x-raw'),
        gst::Caps.from_string('image/jpeg,format=GRAY8;video/x-raw'),
      ]

      not_infrared_caps.each do |cap|
        expect(described_class.infrared?(cap)).to be(false)
      end
    end
  end

  describe '.limit_fps' do
    it 'keeps caps at or under the maximum rate' do
      good_caps = [
        gst::Caps.from_string('video/x-raw,framerate=(fraction)0/1'),
        gst::Caps.from_string("video/x-raw,framerate=(fraction)#{described_class::MAXIMUM_RATE}/1"),
        gst::Caps.from_string("video/x-raw,framerate=(fraction)[0/1,#{described_class::MAXIMUM_RATE}/1]"),
        gst::Caps.from_string('video/x-raw'),
      ]

      good_caps.each do |cap|
        expect(described_class.limit_fps(cap).empty?).to be(false)
      end
    end

    it 'drops caps above the maximum rate' do
      bad_caps = [
        gst::Caps.from_string("video/x-raw,framerate=(fraction)#{described_class::MAXIMUM_RATE + 1}/1"),
      ]

      bad_caps.each do |cap|
        expect(described_class.limit_fps(cap).empty?).to be(true)
      end
    end
  end

  describe '.best_mode' do
    it 'prefers 1080p at the 16:9 ratio' do
      caps_1080 = [
        gst::Caps.from_string('video/x-raw,width=1920,height=1080'),
        gst::Caps.from_string('video/x-raw,width=1920,height=1080;video/x-raw,width=1920,height=1081'),
        gst::Caps.from_string('video/x-raw,width=1920,height=1079;video/x-raw,width=1920,height=1080'),
        gst::Caps.from_string('video/x-raw,width=2160,height=1080;video/x-raw,width=1920,height=1080'),
      ]

      caps_1080.each do |cap|
        expect(described_class.best_mode(cap)).to eq(described_class::Size.new(1920, 1080))
      end
    end

    it 'falls back to 720p when nothing in the optimal band is available' do
      caps_720 = [
        gst::Caps.from_string('video/x-raw,width=1280,height=720'),
        gst::Caps.from_string('video/x-raw,width=1280,height=720;video/x-raw,width=1280,height=1081'),
        gst::Caps.from_string('video/x-raw,width=1280,height=720;video/x-raw,width=1280,height=1080'),
      ]

      caps_720.each do |cap|
        expect(described_class.best_mode(cap)).to eq(described_class::Size.new(1280, 720))
      end
    end

    it 'falls back to the first size seen when nothing is in range' do
      caps_fallback_4k = [
        gst::Caps.from_string('video/x-raw,width=3840,height=2160'),
        gst::Caps.from_string('video/x-raw,width=3840,height=2160;video/x-raw,width=640,height=360'),
      ]

      caps_fallback_4k.each do |cap|
        expect(described_class.best_mode(cap)).to eq(described_class::Size.new(3840, 2160))
      end

      caps_fallback_small = [
        gst::Caps.from_string('video/x-raw,width=640,height=360'),
        gst::Caps.from_string('video/x-raw,width=640,height=360;video/x-raw,width=3840,height=2160'),
      ]

      caps_fallback_small.each do |cap|
        expect(described_class.best_mode(cap)).to eq(described_class::Size.new(640, 360))
      end
    end
  end
end
