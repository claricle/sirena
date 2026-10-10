# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::LineBreakText do
  it "turns a raw HTML break into positioned text runs" do
    text = Sirena::Svg::Text.new.tap do |element|
      element.x = 10
      element.y = 20
      element.font_size = "10"
    end

    described_class.fill(text, " first <BR /> second ")

    expect(text.to_xml).to eq(
      '<text x="10.0" y="20.0" font-size="10">' \
      '<tspan x="10.0">first</tspan>' \
      '<tspan x="10.0" y="32.0">second</tspan></text>',
    )
  end
end
