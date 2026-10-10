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
    slices = zero_total_scene.slices
    [slices.map(&:percentage), slices.map(&:angle),
     slices.map { |item| item.label.text }, slices.map(&:path).uniq.length]
  end

  it "renders zero-total slices without division errors or data suffixes" do
    expect(zero_total_evidence).to eq([[0.0, 0.0], [0.0, 0.0],
                                       ["None", "Also none"], 1])
  end

  it "accepts the released minimal graph shape without slices" do
    graph = { width: 1, height: 1, slices: nil }
    scene = described_class.from_graph(graph)
    expect([scene.id, scene.width, scene.height, scene.title, scene.slices])
      .to eq(["pie", 500.0, 400.0, nil, []])
  end
end
