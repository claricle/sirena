# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Quadrant, "#render" do
  subject(:renderer) { described_class.new }

  let(:source) do
    "quadrantChart\n  title T\n  x-axis L --> R\n  y-axis B --> U\n"
  end
  let(:scene) do
    diagram = Sirena::Parser::Quadrant.new.parse(source)
    Sirena::Layout::Quadrant.new.call(diagram)
  end
  let(:default_colors) { Sirena::Theme::Registry.get(:default).colors }
  let(:quadrant_fills) do
    renderer.render(scene).to_xml.scan(/<rect[^>]*fill="([^"]*)"/).flatten
  end
  let(:default_fills) do
    (0..3).map { |index| default_colors.palette(:quadrant, index) }
  end

  it "paints quadrants from the default palette when there is no theme" do
    renderer.theme = nil

    expect(quadrant_fills).to include(*default_fills)
  end

  it "paints quadrants from the default palette when the theme has no colours" do
    renderer.theme = Sirena::Theme.new(name: "bare")

    expect(quadrant_fills).to include(*default_fills)
  end

  it "paints quadrants from the theme's own palette when it has one" do
    renderer.theme = Sirena::Theme.new(
      colors: { quadrant_palette: %w[#111111 #222222 #333333 #444444] },
    )

    expect(quadrant_fills).to include("#111111", "#444444")
  end
end
