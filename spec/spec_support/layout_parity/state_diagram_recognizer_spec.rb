# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::StateDiagramRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.identity]
    end.sort_by { |item| item.map(&:to_s) }
  end

  it "normalizes generated ordinals and keeps composite ancestry" do
    reference = <<~SVG
      <svg viewBox="0 0 100 100">
        <g class="statediagram-state statediagram-cluster" id="checkout">
          <rect width="100" height="100"/>
        </g>
        <g class="node statediagram-state" id="state-order-2026-7" transform="translate(10 10)">
          <rect width="20" height="20"/>
        </g>
        <g class="node" id="state-checkout_start-8" transform="translate(40 10)">
          <circle r="5"/>
        </g>
      </svg>
    SVG
    sirena = <<~SVG
      <svg viewBox="0 0 100 100">
        <g id="state-checkout"><rect width="100" height="100"/>
          <g id="state-order-2026" transform="translate(10 10)"><rect width="20" height="20"/></g>
          <g id="state-start_3" transform="translate(40 10)"><circle r="5"/><text>[*]</text></g>
        </g>
      </svg>
    SVG

    expected = [
      [:composite, "checkout", nil, :id],
      [:state, "order-2026", "checkout", :id],
      [:"terminal-start", "[*]", "checkout", :label],
    ].sort_by { |item| item.map(&:to_s) }
    expect([recognized(reference), recognized(sirena)]).to eq([expected, expected])
    expect(recognizer.container_kinds).to eq([:composite])
  end

  it "exposes missing composite metadata in a real Sirena render" do
    name = "020_parser_should_handle_state_definitions_with_separation_of_id_19"
    reference = reference_svg("state/#{name}.svg")
    sirena = Sirena.render(corpus_source("state/#{name}.mmd"))

    reference_elements = [
      [:composite, "NotShooting", nil, :id],
      [:state, "Configuring", "NotShooting", :id],
      [:state, "Idle", "NotShooting", :id],
      [:"terminal-start", "[*]", "NotShooting", :label],
    ].sort_by { |item| item.map(&:to_s) }
    sirena_elements = [
      [:state, "Configuring", nil, :id],
      [:state, "Idle", nil, :id],
      [:state, "NotShooting", nil, :id],
      [:"terminal-start", "[*]", nil, :label],
    ].sort_by { |item| item.map(&:to_s) }

    expect(recognized(reference)).to eq(reference_elements)
    expect(recognized(sirena)).to eq(sirena_elements)
  end
end
