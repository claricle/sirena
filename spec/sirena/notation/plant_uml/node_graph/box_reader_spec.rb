# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::BoxReader do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:mixed) do
    "allowmixing\nactor A\nusecase U\nmap M {\n  k => v\n  n => 2\n}\n" \
      "object O {\n  name : String\n  f = 1\n}\nobject P"
  end

  describe "parsing a map" do
    let(:node) { parse(mixed).nodes.fetch("M") }

    it "reads the element as a data node holding a map",
       :aggregate_failures do
      expect(node.kind).to eq(:data)
      expect(node.table.kind).to eq(:map)
      expect(node.table.title).to eq("M")
    end

    it "keeps each row's key and value" do
      expect(node.table.rows.map { |r| [r.key, r.value] })
        .to eq([%w[k v], ["n", "2"]])
    end

    it "keeps a quoted label as the title of the box" do
      graph = parse("allowmixing\nusecase U\nmap \"Pairs\" as m {\n a => b\n}")

      expect(graph.nodes.fetch("m").table.title).to eq("Pairs")
    end

    it "turns a `key *-> target` row into an edge from that row",
       :aggregate_failures do
      edge = parse("allowmixing\nusecase U\nmap M {\n  k *-> U\n}").edges.first

      expect([edge.from.id, edge.to.id, edge.from_row, edge.head])
        .to eq(["M", "U", 0, :target])
    end

    it "ends a `key *-> target::row` edge at the row of the target" do
      graph = parse("allowmixing\nmap N {\n a => b\n c => d\n}\n" \
                    "map M {\n  k *-> N::c\n}")

      expect(graph.edges.first.to_row).to eq(1)
    end

    it "refuses a map without allowmixing" do
      expect { parse("usecase U\nmap M {\n k => v\n}") }
        .to raise_unsupported("statement")
    end

    it "refuses a map whose body never closes" do
      expect { parse("allowmixing\nusecase U\nmap M {\n k => v\n") }
        .to raise_error(Sirena::Parser::ParseError, /unclosed/)
    end
  end

  describe "parsing an object" do
    let(:node) { parse(mixed).nodes.fetch("O") }

    it "reads the element as a data node holding an object",
       :aggregate_failures do
      expect(node.kind).to eq(:data)
      expect(node.table.kind).to eq(:object)
      expect(node.table.rows.map(&:value)).to eq(["name : String", "f = 1"])
    end

    it "names a row by the field it starts with" do
      expect(node.table.rows.map(&:port)).to eq(%w[name f])
    end

    it "reads an object without a body as an empty box" do
      expect(parse(mixed).nodes.fetch("P").table.rows).to be_empty
    end

    it "keeps a quoted label as the title of the box" do
      graph = parse("allowmixing\nusecase U\nobject \"Thing\" as t")

      expect(graph.nodes.fetch("t").table.title).to eq("Thing")
    end

    it "refuses an object without allowmixing" do
      expect { parse("usecase U\nobject O") }.to raise_unsupported("statement")
    end
  end

  describe "yaml" do
    it "is refused: PlantUML's own parser rejects a yaml element here" do
      expect { parse("allowmixing\nusecase U\nyaml Y {\n  a: 1\n}") }
        .to raise_unsupported("statement")
    end
  end

  describe "linking to a row" do
    let(:graph) do
      parse("#{mixed}\nA --> M::n\nM::k --> U\nA --> O::f\nA --> M::none\n" \
            "A --> U::x\nA --> M")
    end
    let(:rows_of_edges) { graph.edges.map { |e| [e.from_row, e.to_row] } }

    it "records the row a link ends at" do
      expect(rows_of_edges.first).to eq([nil, 1])
    end

    it "records the row a link starts at" do
      expect(rows_of_edges[1]).to eq([0, nil])
    end

    it "finds an object row by its field name" do
      expect(rows_of_edges[2]).to eq([nil, 1])
    end

    it "leaves a row nobody has at the edge of the box, as PlantUML does" do
      expect(rows_of_edges[3]).to eq([nil, nil])
    end

    it "ignores a row named on an element that has no rows to name" do
      expect(rows_of_edges[4]).to eq([nil, nil])
    end

    it "ends a link with no row at the edge of the box" do
      expect(rows_of_edges[5]).to eq([nil, nil])
    end

    it "ignores a row named on a json element, which PlantUML draws " \
       "to the edge" do
      json = parse("allowmixing\nusecase U\njson J {\"a\": 1}\nU --> J::a")

      expect(json.edges.first.to_row).to be_nil
    end
  end

  describe "placing a link to a row" do
    let(:scene) do
      Sirena::Notation::PlantUML::NodeGraph::Layout.new.call(parse(source))
    end
    let(:source) do
      "allowmixing\nusecase U\nmap M {\n  k => v\n  n => 2\n}\n" \
        "U --> M::n\nM::k --> U"
    end
    let(:box) { scene.placed.find { |b| b.node.id == "M" } }

    def middle(index)
      Sirena::Notation::PlantUMLData::Boxes::TableBox
        .row_middle(box.node.table, index, box.y)
    end

    def centre(placed)
      placed.x + (placed.width / 2)
    end

    def side_for(other)
      centre(other) >= centre(box) ? box.x + box.width : box.x
    end

    it "ends the line at the middle of the row, on the side it comes from",
       :aggregate_failures do
      other = scene.placed.find { |b| b.node.id == "U" }

      expect(scene.routes.first.points.last)
        .to eq([side_for(other), middle(1)])
    end

    it "starts the line at the middle of the row it leaves" do
      expect(scene.routes.last.points.first.last).to eq(middle(0))
    end

    it "draws the line to the end the layout chose" do
      svg = render(source)
      line = REXML::XPath.first(svg_root(svg), "//line[@stroke-width='1']")
      ends = %w[x2 y2].map { |name| line.attributes[name].to_f }

      expect(ends).to eq(scene.routes.first.points.last)
    end
  end

  describe "rendering" do
    let(:svg) { render(mixed) }

    it "draws the map and object boxes with their titles and rows",
       :aggregate_failures do
      expect(svg_texts(svg))
        .to include("M", "k", "v", "n", "2", "O", "name : String", "f = 1", "P")
    end
  end
end
