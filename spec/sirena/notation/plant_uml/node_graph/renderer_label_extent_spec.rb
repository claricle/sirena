# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Renderer do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:root) do
    svg_root(render("node a\nnode b\nnode c\n" \
                    "a --> b\na --> c : a label as long as it takes to reach"))
  end
  let(:label) do
    REXML::XPath.first(root, "//text[starts-with(text(),'a label')]")
  end
  let(:half) do
    Sirena::TextMeasurement
      .measure_in(:dejavu, label.text, font_size: 12)[:width] / 2
  end

  it "makes the picture wide enough for a label beside the last edge" do
    expect(root.attributes["width"].to_f)
      .to be >= label.attributes["x"].to_f + half
  end
end
