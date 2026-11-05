# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::DataReader do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:mixed) do
    "allowmixing\nactor A\nusecase U\njson J {\n  \"fruit\": \"Apple\",\n  " \
      "\"color\": [\"Red\", \"Green\"]\n}"
  end

  describe "parsing" do
    let(:packaged) do
      "allowmixing\npackage P {\n  json \"Data\" as d {\n    " \
        "\"k\": {\"n\": 1}\n  }\n}"
    end

    it "reads the element as a data node with the rows of its JSON",
       :aggregate_failures do
      node = parse(mixed).nodes.fetch("J")

      expect(node.kind).to eq(:data)
      expect(node.table.rows.map(&:key)).to eq(%w[fruit color])
      expect(node.table.rows.first.value).to eq("Apple")
    end

    it "keeps a nested value inside the element's own row",
       :aggregate_failures do
      graph = parse(mixed)
      color = graph.nodes.fetch("J").table.rows.last

      expect(graph.nodes.keys).to eq(%w[A U J])
      expect(graph.edges).to be_empty
      expect(color.inline.rows.map(&:value)).to eq(%w[Red Green])
    end

    it "titles the box with the element's name" do
      expect(parse(mixed).nodes.fetch("J").table.title).to eq("J")
    end

    it "reads an element whose JSON closes on its own line" do
      graph = parse("allow_mixing\njson J {\"a\": 1}\nusecase U")

      expect(graph.nodes.fetch("J").table.rows.first.value).to eq("1")
    end

    it "keeps a labelled element in its container" do
      expect(parse(packaged).nodes.fetch("d").parent.id).to eq("P")
    end

    it "labels the element with its quoted name" do
      expect(parse(packaged).nodes.fetch("d").lines).to eq(["Data"])
    end

    it "links to the element by name" do
      graph = parse("allowmixing\nactor A\njson J {\"a\": 1}\nA --> J")

      expect(graph.edges.map { |e| e.to.id }).to eq(["J"])
    end

    it "refuses the element without allowmixing" do
      expect { parse("actor A\njson J {\"a\": 1}") }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError,
                        /statement/)
    end

    it "refuses JSON that does not parse" do
      expect { parse("allowmixing\njson J {\n  \"a\": \n") }
        .to raise_error(Sirena::Parser::ParseError, /JSON/)
    end
  end

  describe "rendering" do
    let(:svg) { render(mixed) }

    it "draws the diagram's own shapes beside the one JSON box",
       :aggregate_failures do
      texts = svg_texts(svg)

      expect(texts).to include("A", "U", "J", "fruit", "Apple", "Red", "Green")
      expect(box_rects(svg).size).to eq(1)
    end

    it "keeps two JSON boxes clear of each other" do
      two = "#{mixed}\njson K {\n  \"a\": 1\n}"
      first, second = box_rects(render(two)).sort_by(&:first)

      expect(first[0] + first[2]).to be <= second[0]
    end
  end

  # A JSON box is a background and an outline of the same size.
  def box_rects(svg)
    attributes = %w[x y width height]
    REXML::XPath.match(svg_root(svg), "//rect").map do |rect|
      attributes.map { |name| rect.attributes[name].to_f }
    end.uniq
  end
end
