# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::ErDiagramRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  let(:ordinal_reference) do
    <<~SVG
      <svg viewBox="0 0 30 10">
        <g class="node default" id="entity-ORDER-ITEM-2026-17">
          <rect width="10" height="10"/>
          <text>Order item</text>
        </g>
        <g id="id_entity-ORDER-ITEM-2026-17_entity-CUSTOMER-18_0">
          <path d="M0 0L1 1"/>
        </g>
        <g id="edge-label"><rect width="30" height="10"/><text>owns</text></g>
      </svg>
    SVG
  end

  let(:ordinal_render) do
    <<~SVG
      <svg viewBox="0 0 30 10">
        <g id="entity-ORDER-ITEM-2026">
          <rect width="10" height="10"/>
          <text>Order item</text>
        </g>
      </svg>
    SVG
  end

  let(:ordinal_expected) do
    [[:entity, "ORDER-ITEM-2026", nil, "Order item"]]
  end

  let(:real_expected) do
    car = "CAR string registrationNumber string make string model"
    person = "PERSON string firstName string lastName int age"
    [
      [:entity, "CAR", nil, car],
      [:entity, "PERSON", nil, person],
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

  it "normalizes only the generated ordinal and ignores relationship groups" do
    actual = [recognized(ordinal_reference), recognized(ordinal_render)]
    expected = [[ordinal_expected] * 2, []]
    expect([actual, recognizer.container_kinds]).to eq(expected)
  end

  it "recognizes the same entities and normalized labels in a real pair" do
    path = "er/002_platform_yari2_er_1.mmd"
    expect(recognized_pair(path)).to eq([real_expected] * 2)
  end
end
