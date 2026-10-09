# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::SankeyRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  let(:source) do
    <<~MERMAID
      sankey-beta
        A,B,10
        B,C,5
        A,C,2
    MERMAID
  end

  # Reduced from a real mmdc 11.12.0 render. The committed Sankey corpus case
  # is a circular link that mmdc rejects, so it cannot serve as a reference.
  let(:reference_svg) do
    <<~SVG
      <svg viewBox="0 0 600 400">
        <g class="nodes">
          <g class="node" transform="translate(0, 0)"><rect width="10" height="266"/></g>
          <g class="node" transform="translate(295, 100)"><rect width="10" height="266"/></g>
          <g class="node" transform="translate(590, 0)"><rect width="10" height="266"/></g>
        </g>
        <g class="node-labels">
          <text x="16" y="133">A&#10;12</text>
          <text x="311" y="233">B&#10;10</text>
          <text x="584" y="133">C&#10;7</text>
        </g>
        <g class="links">
          <g class="link"><path d="M10,233C150,233,150,233,295,233"/></g>
          <g class="link"><path d="M305,150C450,150,450,150,590,150"/></g>
          <g class="link"><path d="M10,33C300,33,300,33,590,33"/></g>
        </g>
      </svg>
    SVG
  end

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.identity]
    end.sort_by(&:to_s)
  end

  def expected
    node_keys = %w[A B C].map do |label|
      [:sankey_node, label, :label]
    end
    flow_keys = [["A", "B", 1], ["B", "C", 1],
                 ["A", "C", 1]].map do |key|
      [:sankey_flow, key, :label]
    end
    (node_keys + flow_keys).sort_by(&:to_s)
  end

  it "matches node labels and flow endpoints on both producer shapes" do
    sirena = Sirena.render(source)

    expect([summaries(reference_svg), summaries(sirena)])
      .to eq([expected, expected])
  end
end
