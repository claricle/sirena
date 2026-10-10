# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Theme::Typography do
  describe "its load-order contract" do
    let(:source) do
      File.expand_path("../../../lib/sirena/theme/typography.rb", __dir__)
    end
    let(:typography) do
      Sirena::Theme.const_get(:Typography).from_yaml("font_size_normal: 16.5")
    end

    before do
      stub_const("Sirena::Theme", Class.new)
      load source
    end

    it "loads after the enclosing theme exists" do
      expect(typography.font_size_normal).to eq(16.5)
    end
  end
end
