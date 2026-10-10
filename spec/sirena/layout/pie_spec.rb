# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/pie"

RSpec.describe Sirena::Layout::Pie do
  subject(:scene) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Pie.new }

  it "keeps an empty pie renderable" do
    expect([scene.class, scene.id, scene.width, scene.height, scene.slices])
      .to eq([described_class::Scene, "pie", 450.0, 450.0, []])
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

  it "draws a lone slice as two half arcs, as mmdc does" do
    diagram.slices = [slice("ash", 100)]

    expect(scene.slices.map(&:path)).to eq(
      ["M 225 225 L 225.0 40.0 A 185 185 0 1 1 225.0 410.0 A 185 185 0 1 1 225.0 40.0 Z"],
    )
  end

  it "rounds slice points to four decimals so every platform emits the same text" do
    diagram.slices = [42.5, 28.3, 18.7, 10.5].map { |share| slice("part", share) }
    points = scene.slices.flat_map { |part| part.path.scan(/\d+\.\d+/) << part.label.x.to_s }

    expect(points.map { |point| point.split(".").last.size }.max).to be <= 4
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
      "share", 579.099, 450.0, "Market share", "Share by product",
      "One quarter and three quarters",
      [["slice_0", "25%", include("A 185 185 0 0 1")],
       ["slice_1", "75%", include("A 185 185 0 1 1")]]
    ]
  end
end
