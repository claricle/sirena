# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Svg::Document do
  describe "#to_xml" do
    it "ignores children that cannot render SVG XML" do
      document = described_class.new(width: 10, height: 20)
      expected = document.to_xml
      document.children << Object.new

      expect(document.to_xml).to eq(expected)
    end
  end
end
