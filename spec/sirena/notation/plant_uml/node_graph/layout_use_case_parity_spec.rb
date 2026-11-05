# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Layout do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def xs(svg, *names)
    texts = REXML::XPath.match(REXML::Document.new(svg), "//text")
    names.map { |name| texts.find { |t| t.text == name }.attributes["x"].to_f }
  end

  describe "the actors of one rank" do
    it "stand left to right in the order their first tied link is written",
       :aggregate_failures do
      user, admin = xs(render_fixture("plantuml-lrg-2-8"), "User",
                       "Main Admin")

      expect(user).to be < admin
    end

    it "keep declaration order when no link ties them" do
      left, right = xs(render(":A: as A\n:B: as B\n(U)\nB --> (U)\nA --> (U)"),
                       "A", "B")

      expect(left).to be < right
    end
  end

  describe "a link to a named note" do
    let(:svg) { render_fixture("plantuml-lrg-2-8") }

    it "is a dashed line with no pointer, as the JAR draws it" do
      note_polygons = REXML::XPath.match(REXML::Document.new(svg), "//polygon")
        .select { |p| p.attributes["fill"] == "#FEFFDD" }

      # three note bodies and the two pointers of the notes beside a target
      expect(note_polygons.size).to eq(5)
    end

    it "marks only the notes written beside a target as pointers" do
      edges = parse("(A)\nnote right of (A) : hi\nnote \"n\" as N\n(A) .. N")
        .edges

      expect(edges.map(&:pointer)).to eq([true, nil])
    end
  end

  describe "a stereotype" do
    let(:svg) { render_fixture("plantuml-lrg-2-9") }

    it "is italic" do
      italic = REXML::XPath.match(REXML::Document.new(svg), "//text")
        .select { |t| t.attributes["font-style"] == "italic" }.map(&:text)

      expect(italic).to contain_exactly("«Human»", "«One Shot»",
                                        "«Application»", "«Main»")
    end

    it "sits above an actor's figure, the name staying below it",
       :aggregate_failures do
      texts = REXML::XPath.match(REXML::Document.new(svg), "//text")
      stereotype = texts.find { |t| t.text == "«Human»" }
      name = texts.find { |t| t.text == "User" }

      expect(stereotype.attributes["y"].to_f)
        .to be < name.attributes["y"].to_f - 50
    end
  end
end
