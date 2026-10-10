# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Quadrant do
  subject(:layout) { described_class.new }

  def boundary_diagram
    Sirena::Diagram::Quadrant.new(
      title: "Boundaries", quadrant_1_label: "Keep",
      quadrant_3_label: "Drop",
      points: [point("center", 0.5, 0.5), point("lower-left", 0.49, 0.49)]
    )
  end

  def point(label, x_value, y_value)
    Sirena::Diagram::QuadrantPoint.new(
      label: label, x: x_value, y: y_value,
    )
  end

  def boundary_evidence
    scene = layout.call(boundary_diagram)
    [scene.title.text, scene.points.map(&:quadrant),
     scene.quadrant_labels.map(&:text),
     scene.points.map { |item| [item.x, item.y] }]
  end

  it "assigns center boundaries to one and lower-left values to three" do
    expect(boundary_evidence)
      .to eq(["Boundaries", [1, 3], %w[Keep Drop],
              [[400.0, 300.0], [393.6, 304.4]]])
  end

  it "rejects an invalid point before layout" do
    invalid = Sirena::Diagram::Quadrant.new(points: [point("outside", 2, 0)])
    expect { layout.call(invalid) }.to raise_error(Sirena::Layout::LayoutError)
  end
end
