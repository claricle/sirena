# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph/node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  texts = {
    "plantuml-lrg-2-8" => ["Main Admin", "Use the application", "Start"],
    "plantuml-lrg-2-9" => ["Main Database", "Use the application",
                           "«Human»"],
    "components" => ["Web App", "Mobile App"],
    "plantuml-lrg-7-5" => ["Some Group", "First Component", "FTP", "Foo"],
    "plantuml-lrg-7-18-4" => %w[C c1 p1 po3],
    "plantuml-lrg-8-4-4" => ["foo", "bar5", "[#red,dashed,2]"],
    "plantuml-lrg-8-9-1" => ["Node1", "Node 2", "File 1"],
  }

  texts.each do |name, expected|
    context "with #{name}" do
      let(:svg) { render_fixture(name) }

      it "renders valid SVG" do
        expect(svg_root(svg).name).to eq("svg")
      end

      it "draws the text of the diagram" do
        expect(svg_texts(svg)).to include(*expected)
      end
    end
  end

  it "renders the same SVG twice" do
    renders = Array.new(2) { render_fixture("plantuml-lrg-7-5") }

    expect(renders.uniq.size).to eq(1)
  end

  it "draws a diagram's first block of a multi-diagram file" do
    expect(svg_texts(render_fixture("components"))).not_to include("Database")
  end
end
