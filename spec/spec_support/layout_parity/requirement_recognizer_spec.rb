# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::RequirementRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent]
    end.sort_by { |item| item.map(&:to_s) }
  end

  it "uses the raw reference ids and removes only Sirena's type prefix" do
    reference = <<~SVG
      <svg viewBox="0 0 40 20">
        <g class="node default" id="req-2026"><rect width="10" height="10"/><text>&lt;&lt;Requirement&gt;&gt;</text></g>
        <g class="node default" id="part-7"><rect width="10" height="10"/><text>&lt;&lt;Element&gt;&gt;</text></g>
        <g id="part-7-req-2026-0"><path d="M0 0L1 1"/></g>
      </svg>
    SVG
    sirena = <<~SVG
      <svg viewBox="0 0 40 20">
        <g id="requirement-req-2026"><rect width="10" height="10"/></g>
        <g id="element-part-7"><rect width="10" height="10"/></g>
      </svg>
    SVG

    expected = [[:element, "part-7", nil], [:requirement, "req-2026", nil]]
    expect([recognized(reference), recognized(sirena)]).to eq([expected, expected])
    expect(recognizer.container_kinds).to eq([])
  end

  it "recognizes the same logical nodes in a real reference and render" do
    name = "001_example_requirement_0"
    reference = reference_svg("requirement/#{name}.svg")
    sirena = Sirena.render(corpus_source("requirement/#{name}.mmd"))

    expected = [
      [:element, "test_entity", nil],
      [:requirement, "test_req", nil],
    ]
    expect([recognized(reference), recognized(sirena)]).to eq([expected, expected])
  end
end
