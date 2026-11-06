# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph/node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::Component do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  # A link's line, which is a path once it bends and a line when straight.
  def thick_lines(body)
    root = svg_root(render(body))
    REXML::XPath.match(root,
                       "//*[(self::line or self::path) and @stroke-width='4']")
  end

  def parse_component(body)
    parse(body, family: :component)
  end

  RSpec::Matchers.define :be_inside do |box|
    match do |inner|
      inner.x > box.x && inner.y > box.y &&
        inner.x + inner.width < box.x + box.width &&
        inner.y + inner.height < box.y + box.height
    end
  end

  def node(graph, id)
    graph.nodes.fetch(id)
  end

  describe "declarations" do
    it "reads brackets, the keyword and aliases", :aggregate_failures do
      graph = parse_component("[Web]\ncomponent \"API Gateway\" as API\n" \
                              "component DB as \"Data\"")

      expect(graph.nodes.keys).to eq(%w[Web API DB])
      expect(node(graph, "DB").lines).to eq(["Data"])
    end

    it "reads interfaces in both forms", :aggregate_failures do
      graph = parse_component("interface I1\n() \"Port 2\" as I2")

      expect(graph.nodes.values.map(&:kind)).to eq(%i[interface interface])
      expect(node(graph, "I2").lines).to eq(["Port 2"])
    end

    it "reads deployment shapes", :aggregate_failures do
      graph = parse_component("node N\ndatabase D\ncloud C\nfile F\nfolder O")

      expect(graph.nodes.values.map(&:kind))
        .to eq(%i[node database cloud file folder])
    end

    it "joins a label that runs over several lines" do
      graph = parse_component("cloud c1 as \"a\nb\"\ncloud c2 [x\ny]")

      expect(graph.nodes.values.map(&:lines)).to eq([%w[a b], %w[x y]])
    end
  end

  describe "containers" do
    it "nests a component in a package in a node", :aggregate_failures do
      graph = parse_component("node N {\n package P {\n  [A]\n }\n}")

      expect(node(graph, "A").ancestors.map(&:id)).to eq(%w[N P])
      expect(node(graph, "N")).to be_container
    end

    it "gives an unnamed container its own node" do
      graph = parse_component("cloud {\n [A]\n}")

      expect(node(graph, "A").parent.kind).to eq(:cloud)
    end
  end

  describe "links" do
    it "reads a lollipop link as a socket" do
      expect(parse_component("[A] -(0- [B]").edges.first.head).to eq(:socket)
    end

    it "reads a bracketed line style", :aggregate_failures do
      edge = parse_component("A -[#red,dashed,thickness=2]-> B : x").edges.first

      expect([edge.color, edge.style, edge.width, edge.label])
        .to eq(["red", :dashed, 2, "x"])
    end

    it "reads the second colour of a two-colour link", :aggregate_failures do
      edge = parse_component("A -[#blue;#green]-> B").edges.first

      expect([edge.color, edge.color2]).to eq(%w[blue green])
    end

    it "leaves the second colour empty for a one-colour link" do
      expect(parse_component("A -[#blue]-> B").edges.first.color2).to be_nil
    end

    # JAR 1.2026.6: the second colour is the same spline drawn 2 right, 2 down
    it "draws a two-colour link in each colour, the second offset by 2,2",
       :aggregate_failures do
      strokes = thick_lines("node A\nA -[#blue;#green,thickness=4]-> B")
        .map(&:attributes)
        .map { |attrs| [attrs["stroke"], attrs["transform"]] }

      expect(strokes).to eq([["blue", nil], ["green", "translate(2,2)"]])
    end

    it "draws a one-colour link once" do
      expect(thick_lines("A -[#blue,thickness=4]-> B").size).to eq(1)
    end

    it "drops a hidden link" do
      expect(parse_component("[A] -[hidden]-> [B]").edges).to be_empty
    end

    it "makes an interface of an undeclared name" do
      expect(parse_component("HTTP - [A]").nodes["HTTP"].kind).to eq(:interface)
    end
  end

  describe "layout" do
    def scene(body)
      Sirena::Notation::PlantUML::NodeGraph::Layout.new
        .call(parse_component(body))
    end

    it "keeps a container around its members" do
      placed = scene("package P {\n [A]\n [B]\n}\n[A] --> [B]").placed
      box = placed.find { |p| p.node.id == "P" }

      expect(placed.reject { |p| p.equal?(box) }).to all(be_inside(box))
    end

    it "ranks a chain top to bottom" do
      placed = scene("[A] --> [B]\n[B] --> [C]").placed

      expect(placed.map(&:y)).to eq(placed.map(&:y).sort)
    end

    it "breaks a cycle without raising" do
      expect { scene("[A] --> [B]\n[B] --> [A]") }.not_to raise_error
    end
  end

  describe "unsupported constructs" do
    it "names a preprocessor line" do
      expect do
        render("!procedure x()\n[A]")
      end.to raise_unsupported("preprocessor")
    end

    it "names a legend" do
      expect do
        render("[A]\nlegend\nx\nendlegend")
      end.to raise_unsupported("keyword")
    end
  end
end
