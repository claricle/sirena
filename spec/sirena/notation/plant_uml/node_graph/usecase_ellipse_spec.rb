# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

# Expected radii are the PlantUML JAR's own (1.2026.6) for the same label
# widths, as written into its SVG.
RSpec.describe Sirena::Notation::PlantUML::NodeGraph::UsecaseEllipse do
  def radii(widths)
    described_class.size(widths, 16.4883).map { |side| (side / 2).round(3) }
  end

  it "sizes a one line label by its proportion", :aggregate_failures do
    expect(radii([31.4727])).to eq([25.255, 14.659])
    expect(radii([130.1426])).to eq([80.029, 18.406])
  end

  it "keeps a short label wider than it is tall" do
    expect(radii([7.7314])).to eq([14.006, 11.805])
  end

  it "stops a tall label growing past the greatest proportion" do
    expect(radii([12.8994, 12.8994])).to eq([24.596, 20.277])
  end

  it "holds lines of different widths in the smallest ellipse" do
    expect(radii([83.4258, 96.4961, 23.7139])).to eq([60.765, 32.611])
  end

  it "reaches a line that is not the widest or the first" do
    expect(radii([130.1426, 47.1953])).to eq([85.64, 23.94])
  end
end
