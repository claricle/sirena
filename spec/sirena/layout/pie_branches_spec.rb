# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Pie do
  subject(:layout) { described_class.new }

  def zero_total_scene
    diagram = Sirena::Diagram::Pie.new(
      slices: [slice("None", 0), slice("Also none", 0)],
    )
    layout.call(diagram)
  end

  def slice(label, value)
    Sirena::Diagram::PieSlice.new(label: label, value: value)
  end

  def zero_total_evidence
    scene = zero_total_scene
    [scene.slices, scene.legend.map(&:text)]
  end

  it "draws no slice for a zero total but keeps the legend" do
    expect(zero_total_evidence).to eq([[], ["None", "Also none"]])
  end

  it "accepts the released minimal graph shape without slices" do
    graph = { width: 1, height: 1, slices: nil }
    scene = described_class.from_graph(graph)
    expect([scene.id, scene.width, scene.height, scene.title, scene.slices])
      .to eq(["pie", 450.0, 450.0, nil, []])
  end

  it "starts the largest slice at twelve o'clock, emitted in input order" do
    scene = layout.call(diagram("Small" => 1, "Large" => 3))

    expect(scene.slices.map { |item| item.path[/L (\S+ \S+) A/, 1] })
      .to eq(["40.0 225.0", "225.0 40.0"])
  end

  it "colors sectors by size rank" do
    scene = layout.call(diagram("Small" => 1, "Large" => 3))

    expect(scene.slices.map(&:color_index)).to eq([1, 0])
  end

  it "colors legend rows by size rank" do
    scene = layout.call(diagram("Small" => 1, "Large" => 3))

    expect(scene.legend.map(&:color_index)).to eq([1, 0])
  end

  it "draws no sector for a zero slice but keeps its legend row" do
    scene = layout.call(diagram("None" => 0, "All" => 5))

    expect([scene.slices.map(&:id), scene.legend.length])
      .to eq([["slice_1"], 2])
  end

  def diagram(values)
    slices = values.map { |label, value| slice(label, value) }
    Sirena::Diagram::Pie.new(slices: slices)
  end
end
