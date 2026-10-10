# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/quadrant"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Quadrant do
  subject(:dimensions) do
    point = Sirena::Diagram::QuadrantPoint.new(
      label: "Plain", x: 0.25, y: 0.75,
    )
    diagram = Sirena::Diagram::Quadrant.new(points: [point])
    ir = described_class.call(diagram)
    ir.items.find { |item| item.role == "point" }
      .placements.map(&:dimension)
  end

  it "omits absent optional point styles" do
    expect(dimensions).to eq(%w[x_value y_value marker_size stroke_width])
  end
end
