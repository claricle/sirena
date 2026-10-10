# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::ColorPalette do
  describe "its load-order contract" do
    it "loads after the enclosing theme exists" do
      stub_const("Sirena::Theme", Class.new)
      source = File.expand_path(
        "../../../lib/sirena/theme/color_palette.rb", __dir__
      )

      expect { load source }.not_to raise_error

      palette_class = Sirena::Theme.const_get(:ColorPalette)
      palette = palette_class.from_yaml("background: '#fff'")
      expect(palette.background).to eq("#fff")
    end
  end
end
