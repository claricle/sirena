# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::ClassDiagramRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  let(:ordinal_reference) do
    <<~SVG
      <svg viewBox="0 0 30 10">
        <g id="classId-order-2026-17">
          <rect width="10" height="10"/>
          <text>Order 2026</text>
        </g>
        <g id="id_classId-order-2026-17_classId-tax-2-18_0">
          <path d="M0 0L1 1"/>
        </g>
        <g id="unrelated"><rect width="30" height="10"/></g>
      </svg>
    SVG
  end

  let(:ordinal_render) do
    <<~SVG
      <svg viewBox="0 0 30 10">
        <g id="class-order-2026">
          <rect width="10" height="10"/>
          <text>Order 2026</text>
        </g>
      </svg>
    SVG
  end

  let(:ordinal_expected) do
    [[:class, "order-2026", nil, "Order 2026"]]
  end

  let(:real_expected) do
    [
      [:class, "C1", nil, "Class 1 with text label"],
      [:class, "C2", nil, "C2"],
    ]
  end

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.label]
    end
  end

  def recognized_pair(path)
    reference = reference_svg(path.sub(/\.mmd\z/, ".svg"))
    render = Sirena.render(corpus_source(path))
    [recognized(reference), recognized(render)]
  end

  it "normalizes the generated ordinal without shortening the author id" do
    actual = [recognized(ordinal_reference), recognized(ordinal_render)]
    expected = [[ordinal_expected] * 2, []]
    expect([actual, recognizer.container_kinds]).to eq(expected)
  end

  it "recognizes the same logical nodes in a real reference and render" do
    path = "class/001_rendering_classdiagram-elk-v3_spec_class_0.mmd"
    expect(recognized_pair(path)).to eq([real_expected] * 2)
  end
end
