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

  def synthetic_reference
    <<~SVG
      <svg viewBox="0 0 40 20">
        <g class="node" id="req-2026"><rect width="10" height="10"/><text>&lt;&lt;Requirement&gt;&gt;</text></g>
        <g class="node" id="part-7"><rect width="10" height="10"/><text>&lt;&lt;Element&gt;&gt;</text></g>
      </svg>
    SVG
  end

  def synthetic_sirena
    <<~SVG
      <svg viewBox="0 0 40 20">
        <g id="requirement-req-2026"><rect width="10" height="10"/></g>
        <g id="element-part-7"><rect width="10" height="10"/></g>
      </svg>
    SVG
  end

  def synthetic_elements
    [[:element, "part-7", nil], [:requirement, "req-2026", nil]]
  end

  def real_sides
    name = "001_example_requirement_0"
    [reference_svg("requirement/#{name}.svg"),
     Sirena.render(corpus_source("requirement/#{name}.mmd"))]
  end

  def real_elements
    [[:element, "test_entity", nil], [:requirement, "test_req", nil]]
  end

  it "uses the raw reference ids and removes only Sirena's type prefix" do
    actual = [recognized(synthetic_reference), recognized(synthetic_sirena),
              recognizer.container_kinds]

    expect(actual).to eq([synthetic_elements, synthetic_elements, []])
  end

  it "recognizes the same logical nodes in a real reference and render" do
    reference, sirena = real_sides

    expect([recognized(reference), recognized(sirena)])
      .to eq([real_elements, real_elements])
  end
end
