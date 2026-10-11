# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/treemap"

RSpec.describe Sirena::Layout::Treemap do
  let(:graph) do
    {
      width: 80, height: 40,
      cells: [
        {
          label: "Styled", value: 1, x: 0, y: 0,
          width: 40, height: 40, depth: 0,
          css_class: "fill-only", children: []
        },
        {
          label: "Unstyled", value: 1, x: 40, y: 0,
          width: 40, height: 40, depth: 1, children: []
        }
      ],
      class_defs: { "fill-only" => "fill: #abc" }
    }
  end
  let(:scene) { described_class.from_graph(graph, theme: Sirena::Theme.new) }

  it "falls back when an explicit theme has no color palette" do
    expect(scene.cells.map { |cell| [cell.fill, cell.stroke] })
      .to eq([["#abc", "#333"], ["#ffffb3", "#333"]])
  end
end
