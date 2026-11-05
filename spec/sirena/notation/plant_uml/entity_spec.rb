# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph/node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::Entity do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def source(body)
    "@startuml\n#{body}\n@enduml\n"
  end

  def type_of(body)
    Sirena::Notation::PlantUML.parse(source(body)).type
  end

  def graph_of(body)
    Sirena::Notation::PlantUML.parse(source(body)).diagram
  end

  let(:fixture_dir) do
    File.expand_path("../../../fixtures/plantuml_entity_archimate", __dir__)
  end

  let(:user) do
    "entity \"User\" as u {\n  *id : number <<generated>>\n  --\n  " \
      "*name : text\n  note : text\n}"
  end

  describe ".entity?" do
    it "claims an entity block", :aggregate_failures do
      expect(type_of(user)).to eq(:entity_diagram)
      expect(described_class.entity?(source("entity A {\n}"))).to be(true)
    end

    it "claims a cardinality link between bare names" do
      expect(type_of("a }|..|| b")).to eq(:entity_diagram)
    end

    it "keeps a field named like an activity keyword inside the block" do
      body = "entity A {\n  start : date\n  if : text\n}\nA ||--o{ B"

      expect(type_of(body)).to eq(:entity_diagram)
    end

    it "leaves a sequence participant alone" do
      expect(type_of("entity A\nA -> B : hi")).to eq(:sequence_diagram)
    end

    it "leaves a class diagram alone", :aggregate_failures do
      body = "class C\nentity E {\n}"

      expect(described_class.entity?(source(body))).to be(false)
      expect(type_of("class C")).to eq(:class_diagram)
    end
  end

  describe "entity blocks" do
    it "reads the name, alias and sections", :aggregate_failures do
      node = graph_of(user).nodes.fetch("u")

      expect([node.kind, node.lines]).to eq([:entity, ["User"]])
      expect(node.sections.map { |rows| rows.map(&:text) })
        .to eq([["id : number «generated»"], ["name : text", "note : text"]])
    end

    it "marks a key field with a leading star", :aggregate_failures do
      node = graph_of(user).nodes.fetch("u")

      expect(node.sections.flatten.map(&:key)).to eq([true, true, false])
    end

    it "splits sections on every divider form" do
      node = graph_of("entity A {\n a\n ==\n b\n ..\n c\n __\n d\n}")
        .nodes.fetch("A")

      expect(node.sections.map { |rows| rows.map(&:text) })
        .to eq([["a"], ["b"], ["c"], ["d"]])
    end

    it "reads a titled divider as a divider" do
      node = graph_of("entity A {\n a\n -- keys --\n b\n}").nodes.fetch("A")

      expect(node.sections.size).to eq(2)
    end

    it "drops an empty section", :aggregate_failures do
      node = graph_of("entity A {\n --\n a\n --\n}").nodes.fetch("A")

      expect(node.sections.size).to eq(1)
      expect(graph_of("entity E {\n}").nodes.fetch("E").sections).to eq([])
    end

    it "reads a body-less entity", :aggregate_failures do
      graph = graph_of("entity B\nB ||--|{ B2\nentity \"Q\" as q {\n}")

      expect(graph.nodes.fetch("B").sections).to eq([])
      expect(graph.nodes.keys).to eq(%w[B B2 q])
    end
  end

  describe "cardinality links" do
    def link(arrow)
      graph_of("entity A {\n}\nentity B {\n}\nA #{arrow} B : owns")
        .edges.first
    end

    {
      "}|..||" => [%i[many one], %i[one one], :dashed],
      "}o--o|" => [%i[many zero], %i[one zero], :solid],
      "||..o{" => [%i[one one], %i[many zero], :dashed],
      "|o--|{" => [%i[one zero], %i[many one], :solid],
    }.each do |arrow, (from, to, style)|
      it "reads #{arrow}" do
        edge = link(arrow)

        expect([edge.ends, edge.style]).to eq([[from, to], style])
      end
    end

    it "keeps the label and no arrowhead", :aggregate_failures do
      edge = link("}|..||")

      expect(edge.label).to eq("owns")
      expect(edge.head).to be_nil
    end
  end

  describe "rendering" do
    let(:svg) do
      Sirena.render(File.read(File.join(fixture_dir,
                                        "entity_card_accounts.puml")),
                    notation: :plantuml)
    end

    it "draws the whole fixture", :aggregate_failures do
      expect(svg_root(svg).name).to eq("svg")
      expect(svg_texts(svg)).to include("User", "Stream", "E",
                                        "user_id : number «generated»")
    end

    it "draws a spot, a bullet and a rule per compartment",
       :aggregate_failures do
      doc = REXML::Document.new(render(user))

      expect(REXML::XPath.match(doc, "//circle").size).to eq(3)
      expect(REXML::XPath.match(doc, "//line").size).to eq(2)
    end

    it "draws crow's feet, bars and rings", :aggregate_failures do
      doc = REXML::Document.new(render("a }o..|| b\nb |o--|{ c"))

      expect(REXML::XPath.match(doc, "//line").size).to eq(10)
      expect(REXML::XPath.match(doc, "//circle[@fill='#FFFFFF']").size).to eq(2)
    end

    it "sizes a body-less entity to its name" do
      expect(svg_texts(render("entity Customer\nCustomer ||--o{ Order")))
        .to include("Customer", "Order")
    end
  end

  describe Sirena::Notation::PlantUML::NodeGraph::CrowsFoot do
    it "reads both ends of every glyph", :aggregate_failures do
      expect(described_class.parse("||", "o|"))
        .to eq([%i[one one], %i[one zero]])
      expect(described_class.parse("}o", "|{"))
        .to eq([%i[many zero], %i[many one]])
    end

    it "refuses a glyph it does not know" do
      expect { described_class.parse("xx", "||") }.to raise_error(KeyError)
    end
  end
end
