# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Quadrant, "#render" do
  def label(text, x: 10, y: 10)
    Sirena::Layout::Quadrant::Label.new(
      text: text, x: x, y: y, font_size: 14,
      text_anchor: "middle", baseline: "middle"
    )
  end

  it "rejects a bare positioned Hash" do
    expect { described_class.new.render(width: 100, height: 100) }
      .to raise_error(NoMethodError)
  end

  it "renders the final label attached to each Scene quadrant" do
    quadrant = Sirena::Layout::Quadrant::Rect.new(
      number: 1, x: 0, y: 0, width: 50, height: 50,
      label: label("Attached", x: 7, y: 9)
    )
    scene = Sirena::Layout::Quadrant::Scene.new(
      width: 100, height: 100, quadrants: [quadrant],
      quadrant_labels: [label("Legacy inference", x: 25, y: 25)]
    )

    xml = described_class.new.render(scene).to_xml

    expect(xml).to include(">Attached</text>")
    expect(xml).not_to include("Legacy inference")
  end

  it "receives each label already associated by Layout" do
    source = <<~MERMAID
      quadrantChart
        quadrant-1 First
        quadrant-3 Third
    MERMAID
    diagram = Sirena::Parser::Quadrant.new.parse(source)

    scene = Sirena::Layout::Quadrant.new.call(diagram)

    expect(scene.quadrants.map { |quadrant| quadrant.label&.text })
      .to eq(["First", nil, "Third", nil])
  end
end
