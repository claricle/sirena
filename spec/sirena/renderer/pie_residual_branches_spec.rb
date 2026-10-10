# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Pie, "#render" do
  subject(:renderer) { described_class.new }

  let(:graph) do
    { slices: [{ label: "A", percentage: 100.0, angle: 360.0 }] }
  end
  let(:fill) do
    renderer.render(graph).children.grep(Sirena::Svg::Path).first.fill
  end

  it "falls back to the palette when the theme names no slice colour" do
    expect(fill).to eq(described_class::DEFAULT_COLORS.first)
  end

  it "paints the first slice from the default palette without a theme" do
    renderer.theme = nil

    expect(fill).to eq(described_class::DEFAULT_COLORS.first)
  end
end
