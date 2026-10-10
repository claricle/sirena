# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::ColorPalette do
  describe "its load-order contract" do
    let(:source) do
      File.expand_path("../../../lib/sirena/theme/color_palette.rb", __dir__)
    end
    let(:palette) do
      Sirena::Theme.const_get(:ColorPalette).from_yaml("background: '#fff'")
    end

    before do
      stub_const("Sirena::Theme", Class.new)
      load source
    end

    it "loads after the enclosing theme exists" do
      expect(palette.background).to eq("#fff")
    end
  end
end
