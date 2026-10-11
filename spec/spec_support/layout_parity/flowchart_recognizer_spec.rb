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
    reference, sirena = flowchart_sides("configuration_spec-67574f4a")

    expect([recognized(reference), recognized(sirena)])
      .to eq([expected_nodes] * 2)
  end

  it "recognizes direct node ids created by node and subgraph collisions" do
    names = %w[current2-d5a29a70 current2-420bf58f]
    pairs = names.map do |name|
      flowchart_sides(name).map { |svg| node_parents(svg).fetch("B") }
    end

    expect(pairs).to eq([["A", "A"], ["A", "A"]])
  end
end
