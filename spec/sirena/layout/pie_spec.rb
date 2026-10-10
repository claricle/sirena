# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/pie"

RSpec.describe Sirena::Layout::Pie do
  subject(:scene) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Pie.new }

  it "keeps an empty pie renderable" do
    expect([scene.class, scene.id, scene.width, scene.height, scene.slices])
      .to eq([described_class::Scene, "pie", 500.0, 400.0, []])
  end

  it "transforms populated slices and their proportions" do
    populate_diagram
    expect(populated_geometry).to match(expected_geometry)
  end

  it "lays out shared data IR identically to the private model" do
    populate_diagram
    ir = Sirena::Notation::Mermaid::IRAdapters::Pie.call(diagram)
    ir_scene = described_class.new.call(ir)

    expect(populated_geometry(ir_scene)).to eq(populated_geometry)
  end

  def populate_diagram
    diagram.slices = [slice("Small", 1), slice("Large", 3)]
    diagram.id = "share"
    diagram.title = "Market share"
    diagram.show_data = true
    populate_accessibility
  end

  def populate_accessibility
    diagram.acc_title = "Share by product"
    diagram.acc_description = "One quarter and three quarters"
  end

  def populated_geometry(value = scene)
    scene_identity(value) + [slice_geometry(value)]
  end

  def scene_identity(value)
    [value.id, value.width, value.height, value.title.text,
     value.acc_title, value.acc_description]
  end

  def slice_geometry(value)
    value.slices.map { |slice| [slice.id, slice.label.text, slice.path] }
  end

  def slice(label, value)
    Sirena::Diagram::PieSlice.new(label: label, value: value)
  end

  def expected_geometry
    [
      "share", 500.0, 460.0, "Market share", "Share by product",
      "One quarter and three quarters",
      [["slice_0", "Small: 25.0%", include("A 150 150 0 0 1")],
       ["slice_1", "Large: 75.0%", include("A 150 150 0 1 1")]]
    ]
  end
end
