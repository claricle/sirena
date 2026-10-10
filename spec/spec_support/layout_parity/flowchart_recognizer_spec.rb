# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::FlowchartRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  let(:expected_nodes) do
    [
      [:node, "A", nil, "Christmas"],
      [:node, "B", nil, "Go shopping"],
      [:node, "C", nil, "Let me think"],
      [:node, "D", nil, "Laptop"],
      [:node, "E", nil, "iPhone"],
      [:node, "F", nil, "Car"],
    ]
  end

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.label]
    end
  end

  def node_parents(svg)
    extract(svg, recognizer).elements.filter_map do |element|
      [element.key, element.parent] if element.kind == :node
    end.to_h
  end

  it "matches semantic node identities in a real reference and render" do
    reference, sirena = flowchart_sides("001_config_0")

    expect([recognized(reference), recognized(sirena)])
      .to eq([expected_nodes] * 2)
  end

  it "recognizes direct node ids created by node and subgraph collisions" do
    names = %w[009_platform_current2_flowchart_8 011_platform_current2_6]
    pairs = names.map do |name|
      flowchart_sides(name).map { |svg| node_parents(svg).fetch("B") }
    end

    expect(pairs).to eq([["A", "A"], ["A", "A"]])
  end
end
