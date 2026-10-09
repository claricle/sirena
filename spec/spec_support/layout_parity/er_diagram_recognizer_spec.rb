# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::ErDiagramRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.label]
    end
  end

  it "normalizes only the generated ordinal and ignores relationship groups" do
    reference = <<~SVG
      <svg viewBox="0 0 30 10">
        <g class="node default" id="entity-ORDER-ITEM-2026-17"><rect width="10" height="10"/><text>Order item</text></g>
        <g id="id_entity-ORDER-ITEM-2026-17_entity-CUSTOMER-18_0"><path d="M0 0L1 1"/></g>
        <g id="edge-label"><rect width="30" height="10"/><text>owns</text></g>
      </svg>
    SVG
    sirena = <<~SVG
      <svg viewBox="0 0 30 10">
        <g id="entity-ORDER-ITEM-2026"><rect width="10" height="10"/><text>Order item</text></g>
      </svg>
    SVG

    expected = [[:entity, "ORDER-ITEM-2026", nil, "Order item"]]
    expect([recognized(reference), recognized(sirena)]).to eq([expected, expected])
    expect(recognizer.container_kinds).to eq([])
  end

  it "recognizes the same entities and normalized labels in a real pair" do
    name = "002_platform_yari2_er_1"
    reference = reference_svg("er/#{name}.svg")
    sirena = Sirena.render(corpus_source("er/#{name}.mmd"))

    expected = [
      [:entity, "CAR", nil, "CAR string registrationNumber string make string model"],
      [:entity, "PERSON", nil, "PERSON string firstName string lastName int age"],
    ]
    expect([recognized(reference), recognized(sirena)]).to eq([expected, expected])
  end
end
