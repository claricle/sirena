# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::ClassDiagramRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.label]
    end
  end

  it "normalizes the generated ordinal without shortening the author id" do
    reference = <<~SVG
      <svg viewBox="0 0 30 10">
        <g id="classId-order-2026-17"><rect width="10" height="10"/><text>Order 2026</text></g>
        <g id="id_classId-order-2026-17_classId-tax-2-18_0"><path d="M0 0L1 1"/></g>
        <g id="unrelated"><rect width="30" height="10"/></g>
      </svg>
    SVG
    sirena = <<~SVG
      <svg viewBox="0 0 30 10">
        <g id="class-order-2026"><rect width="10" height="10"/><text>Order 2026</text></g>
      </svg>
    SVG

    expected = [[:class, "order-2026", nil, "Order 2026"]]
    expect([recognized(reference), recognized(sirena)]).to eq([expected, expected])
    expect(recognizer.container_kinds).to eq([])
  end

  it "recognizes the same logical nodes in a real reference and render" do
    name = "001_rendering_classdiagram-elk-v3_spec_class_0"
    reference = reference_svg("class/#{name}.svg")
    sirena = Sirena.render(corpus_source("class/#{name}.mmd"))

    expected = [
      [:class, "C1", nil, "Class 1 with text label"],
      [:class, "C2", nil, "C2"],
    ]
    expect([recognized(reference), recognized(sirena)]).to eq([expected, expected])
  end
end
