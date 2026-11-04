# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph/node_graph_helpers"

# Behaviour of the use case and component graph that the family specs leave
# untouched: arrow ends, settings, colours, shared names and degenerate links.
RSpec.describe Sirena::Notation::PlantUML::NodeGraph do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def polygons(svg)
    REXML::XPath.match(svg_root(svg), "//polygon")
  end

  describe "arrow ends" do
    it "points the head at the source of a reversed link" do
      svg = render("usecase A\nusecase B\nA <-- B")

      expect(polygons(svg).size).to eq(1)
    end

    it "draws a head at both ends of a two-way link" do
      svg = render("usecase A\nusecase B\nA <--> B")

      expect(polygons(svg).size).to eq(2)
    end

    it "draws a socket circle for a required interface", :aggregate_failures do
      graph = parse("[A]\n[B]\n[A] -(0- [B]", family: :component)
      svg = render("[A]\n[B]\n[A] -(0- [B]")

      expect(graph.edges.first.head).to eq(:socket)
      expect(REXML::XPath.match(svg_root(svg), "//circle[@fill='#FFFFFF']"))
        .not_to be_empty
    end

    it "keeps a plain line headless" do
      expect(render("usecase A\nusecase B\nA -- B")).not_to include("<polygon")
    end

    it "aims a head along the default axis when both ends coincide" do
      heads = Sirena::Notation::PlantUML::NodeGraph::Heads

      expect(heads.unit([3.0, 4.0], [3.0, 4.0])).to eq([0.0, 1.0])
    end
  end

  describe "settings" do
    it "skips a skinparam block and keeps reading", :aggregate_failures do
      graph = parse("skinparam node {\n  BackgroundColor red\n}\n" \
                    "skinparam shadowing false\nactor A")

      expect(graph.nodes.keys).to eq(%w[A])
    end

    it "reads the direction in both orientations", :aggregate_failures do
      expect(parse("top to bottom direction", family: :usecase).direction)
        .to eq(:top_to_bottom)
      expect(parse("left to right direction", family: :component).direction)
        .to eq(:left_to_right)
    end

    it "reads a diagram that has no @startuml line", :aggregate_failures do
      parser = described_class::Parser.new(direction: :top_to_bottom,
                                           default_kind: :actor)

      graph = parser.parse("actor A\nA --> B")

      expect(graph.nodes.keys).to eq(%w[A B])
    end
  end

  describe "names and colours" do
    it "keeps one node when a name is declared twice", :aggregate_failures do
      graph = parse("actor A\nusecase A")

      expect(graph.nodes.size).to eq(1)
      expect(graph.nodes["A"].kind).to eq(:usecase)
    end

    it "draws a hex-coloured and a named-coloured link", :aggregate_failures do
      svg = render("usecase A\nusecase B\n" \
                   "A -[#33668E]-> B\nB -[#red]-> A")

      expect(svg).to include('stroke="#33668E"')
      expect(svg).to include('stroke="red"')
    end

    it "fills a shape with a hex and a named colour", :aggregate_failures do
      svg = render("usecase A #33668E\nusecase B #pink")

      expect(svg).to include('fill="#33668E"')
      expect(svg).to include('fill="pink"')
    end

    it "fills a coloured container and leaves a plain one open",
       :aggregate_failures do
      svg = render("rectangle R #ccf {\n  (A)\n}\nrectangle Q {\n  (B)\n}")

      expect(svg).to include('fill="#ccf"')
      expect(svg).to include('fill="none"')
    end
  end

  describe "shapes" do
    it "bolds only the first line of a container title" do
      svg = render("rectangle \"Shop\\nfront\" as R {\n  (A)\n}")

      expect(svg_texts(svg)).to include("Shop", "front")
    end

    it "draws a database, a node and a cloud", :aggregate_failures do
      svg = render("database D\nnode N\ncloud C\nfile F\nD --> N\nN --> C")

      expect(REXML::XPath.match(svg_root(svg), "//path").size).to be >= 3
      expect(svg_texts(svg)).to include("D", "N", "C", "F")
    end
  end

  describe "degenerate geometry" do
    it "lays out a diagram with no nodes", :aggregate_failures do
      graph = described_class::Graph.new(direction: :left_to_right)

      scene = described_class::Layout.new.call(graph)

      expect(scene.placed).to be_empty
      expect(scene.width).to eq(2 * described_class::Layout::MARGIN)
    end

    it "keeps a link between boxes with one centre at that centre" do
      box = described_class::Placed.new(node: nil, x: 0.0, y: 0.0, width: 20.0,
                                        height: 10.0, depth: 0)

      clipped = described_class::Layout.new.send(:clip, box, [10.0, 5.0],
                                                 [10.0, 5.0])

      expect(clipped).to eq([10.0, 5.0])
    end
  end

  describe "degenerate links" do
    it "draws nothing for a link from a node to itself", :aggregate_failures do
      graph = parse("actor A\nA --> A")

      expect(render("usecase A\nA --> A")).not_to include("<polygon")
      expect(graph.edges.size).to eq(1)
    end

    it "lays out a diamond of links", :aggregate_failures do
      svg = render("usecase A\nusecase B\nusecase C\nusecase D\n" \
                   "A --> B\nA --> C\nB --> D\nC --> D")

      expect(polygons(svg).size).to eq(4)
    end

    it "draws a link from a container to a node inside it" do
      svg = render("rectangle R {\n  (A)\n}\nR --> A")

      expect(svg).to start_with("<svg")
    end
  end
end
