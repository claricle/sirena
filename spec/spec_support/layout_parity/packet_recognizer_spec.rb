# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::PacketRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.identity]
    end
  end

  it "uses the nearest contained text instead of bit ranges or the title" do
    svg = <<~SVG
      <svg viewBox="0 0 100 100">
        <text x="50" y="10">Packet title</text>
        <rect x="10" y="20" width="80" height="40"/>
        <text x="50" y="42">payload</text>
        <text x="50" y="59">0-7</text>
      </svg>
    SVG

    expect(recognized(svg)).to eq([[:field, "payload", nil, :label]])
    expect(recognizer.container_kinds).to eq([])
  end

  it "recognizes the same packet fields in a real reference and render" do
    name = "001_rendering_packet_spec_packet_0"
    reference = reference_svg("packet/#{name}.svg")
    sirena = Sirena.render(corpus_source("packet/#{name}.mmd"))
    expected = [[:field, "hello", nil, :label]]

    expect([recognized(reference), recognized(sirena)]).to eq([expected, expected])
  end
end
