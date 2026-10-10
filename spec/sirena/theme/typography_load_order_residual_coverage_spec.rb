# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::Typography do
  describe "its load-order contract" do
    it "loads after the enclosing theme exists" do
      stub_const("Sirena::Theme", Class.new)
      source = File.expand_path(
        "../../../lib/sirena/theme/typography.rb", __dir__
      )

      expect { load source }.not_to raise_error

      typography_class = Sirena::Theme.const_get(:Typography)
      typography = typography_class.from_yaml("font_size_normal: 16.5")
      expect(typography.font_size_normal).to eq(16.5)
    end
  end
end
