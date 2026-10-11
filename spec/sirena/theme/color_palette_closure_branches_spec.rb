# frozen_string_literal: true

require "spec_helper"
require "sirena/theme/completion"

RSpec.describe Sirena::Theme::ColorPalette do
  subject(:colors) do
    described_class.new(radar_palette: %w[#aa0000 #00bb00], flow_palette: [])
  end

  it "wraps the index past the end of a named palette" do
    expect([colors.palette(:radar, 0), colors.palette(:radar, 3)])
      .to eq(%w[#aa0000 #00bb00])
  end

  it "rejects a palette name it does not know" do
    expect { colors.palette(:rainbow, 0) }
      .to raise_error(KeyError, "unknown palette: :rainbow")
  end

  it "rejects a known palette the theme leaves empty" do
    expect { colors.palette(:flow, 0) }
      .to raise_error(KeyError, "theme defines no flow palette")
  end

  it "rejects a known palette the theme leaves unset" do
    expect { colors.palette(:pie, 0) }
      .to raise_error(KeyError, "theme defines no pie palette")
  end
end
