# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/treemap"

RSpec.describe Sirena::Layout::Treemap do
  let(:graph) do
    {
      width: 80, height: 40,
      cells: [{
        label: "Unstyled", value: 1, x: 0, y: 0,
        width: 80, height: 40, depth: 0,
        css_class: "fill-only", children: []
      }],
      class_defs: { "fill-only" => "fill: #abc" }
    }
  end
  let(:scene) { described_class.from_graph(graph, theme: Sirena::Theme.new) }

  it "falls back when an explicit theme has no color palette" do
    expect([scene.cells.first.fill, scene.cells.first.stroke])
      .to eq(["#abc", "#333"])
  end
end
