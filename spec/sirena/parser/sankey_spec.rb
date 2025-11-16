# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sankey"

RSpec.describe Sirena::Parser::SankeyParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    it "parses a simple sankey diagram" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
      SANKEY

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::SankeyDiagram)
      expect(diagram.flows.length).to eq(2)
      expect(diagram.flows[0].source).to eq("A")
      expect(diagram.flows[0].target).to eq("B")
      expect(diagram.flows[0].value).to eq(10.0)
    end

    it "parses sankey with float values" do
      source = <<~SANKEY
        sankey-beta
        A,B,10.5
        B,C,20.75
      SANKEY

      diagram = parser.parse(source)

      expect(diagram.flows.length).to eq(2)
      expect(diagram.flows[0].value).to eq(10.5)
      expect(diagram.flows[1].value).to eq(20.75)
    end

    it "parses sankey with node labels" do
      source = <<~SANKEY
        sankey-beta
        Source [Energy Source]
        Process [Processing Plant]
        Source,Process,100
      SANKEY

      diagram = parser.parse(source)

      expect(diagram.nodes.length).to eq(2)
      expect(diagram.nodes[0].id).to eq("Source")
      expect(diagram.nodes[0].label).to eq("Energy Source")
      expect(diagram.nodes[1].id).to eq("Process")
      expect(diagram.nodes[1].label).to eq("Processing Plant")
      expect(diagram.flows.length).to eq(1)
    end

    it "auto-discovers nodes from flows" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
        C,D,15
      SANKEY

      diagram = parser.parse(source)

      # Nodes should be auto-discovered from flows
      node_ids = diagram.all_node_ids
      expect(node_ids).to contain_exactly("A", "B", "C", "D")
    end

    it "parses sankey with underscores in node IDs" do
      source = <<~SANKEY
        sankey-beta
        node_1,node_2,10
        node_2,node_3,5
      SANKEY

      diagram = parser.parse(source)

      expect(diagram.flows.length).to eq(2)
      expect(diagram.flows[0].source).to eq("node_1")
      expect(diagram.flows[0].target).to eq("node_2")
    end

    it "parses the fixture file" do
      source = <<~SANKEY
        sankey-beta
              __proto__,A,0.597
              A,__proto__,0.403
      SANKEY

      diagram = parser.parse(source)

      expect(diagram.flows.length).to eq(2)
      expect(diagram.flows[0].source).to eq("__proto__")
      expect(diagram.flows[0].target).to eq("A")
      expect(diagram.flows[0].value).to eq(0.597)
      expect(diagram.flows[1].source).to eq("A")
      expect(diagram.flows[1].target).to eq("__proto__")
      expect(diagram.flows[1].value).to eq(0.403)
    end

    it "calculates total flow" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
        A,D,5
      SANKEY

      diagram = parser.parse(source)

      expect(diagram.total_flow).to eq(35.0)
      expect(diagram.max_flow).to eq(20.0)
      expect(diagram.min_flow).to eq(5.0)
    end

    it "identifies source and sink nodes" do
      source = <<~SANKEY
        sankey-beta
        Source,Middle,10
        Middle,Sink,10
      SANKEY

      diagram = parser.parse(source)

      expect(diagram.source_nodes).to include("Source")
      expect(diagram.sink_nodes).to include("Sink")
    end

    it "calculates node inflow and outflow" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,7
        B,D,3
      SANKEY

      diagram = parser.parse(source)

      expect(diagram.total_inflow("B")).to eq(10.0)
      expect(diagram.total_outflow("B")).to eq(10.0)
      expect(diagram.total_inflow("A")).to eq(0.0)
      expect(diagram.total_outflow("D")).to eq(0.0)
    end

    it "validates parsed sankey" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
      SANKEY

      diagram = parser.parse(source)

      expect(diagram.valid?).to be true
    end

    it "raises error on invalid syntax" do
      source = "invalid sankey syntax"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "raises error on missing header" do
      source = <<~SANKEY
        A,B,10
        B,C,20
      SANKEY

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end
  end
end