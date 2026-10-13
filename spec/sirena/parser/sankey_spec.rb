# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sankey"

RSpec.describe Sirena::Parser::Sankey, :aggregate_failures do
  let(:parser) { described_class.new }

  context "when parsing a simple sankey diagram" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram" do
      expect(diagram).to be_a(Sirena::Diagram::Sankey)
    end

    it "retains diagram.flows.length" do
      expect(diagram.flows.length).to eq(2)
    end

    it "retains diagram.flows 0 .source" do
      expect(diagram.flows[0].source).to eq("A")
    end

    it "retains diagram.flows 0 .target" do
      expect(diagram.flows[0].target).to eq("B")
    end

    it "retains diagram.flows 0 .value" do
      expect(diagram.flows[0].value).to eq(10.0)
    end
  end

  context "when parsing sankey with float values" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        A,B,10.5
        B,C,20.75
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.flows.length" do
      expect(diagram.flows.length).to eq(2)
    end

    it "retains diagram.flows 0 .value" do
      expect(diagram.flows[0].value).to eq(10.5)
    end

    it "retains diagram.flows 1 .value" do
      expect(diagram.flows[1].value).to eq(20.75)
    end
  end

  context "when parsing sankey with node labels" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        Source [Energy Source]
        Process [Processing Plant]
        Source,Process,100
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.nodes.length" do
      expect(diagram.nodes.length).to eq(2)
    end

    it "retains diagram.nodes 0 .id" do
      expect(diagram.nodes[0].id).to eq("Source")
    end

    it "retains diagram.nodes 0 .label" do
      expect(diagram.nodes[0].label).to eq("Energy Source")
    end

    it "retains diagram.nodes 1 .id" do
      expect(diagram.nodes[1].id).to eq("Process")
    end

    it "retains diagram.nodes 1 .label" do
      expect(diagram.nodes[1].label).to eq("Processing Plant")
    end

    it "retains diagram.flows.length" do
      expect(diagram.flows.length).to eq(1)
    end
  end

  context "when auto-discovers nodes from flows" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
        C,D,15
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains node_ids" do
      node_ids = diagram.all_node_ids

      expect(node_ids).to contain_exactly("A", "B", "C", "D")
    end
  end

  context "when parsing sankey with underscores in node IDs" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        node_1,node_2,10
        node_2,node_3,5
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.flows.length" do
      expect(diagram.flows.length).to eq(2)
    end

    it "retains diagram.flows 0 .source" do
      expect(diagram.flows[0].source).to eq("node_1")
    end

    it "retains diagram.flows 0 .target" do
      expect(diagram.flows[0].target).to eq("node_2")
    end
  end

  context "when parsing __proto__ as an ordinary node name" do
    let(:source) do
      <<~SANKEY
        sankey-beta
              __proto__,A,0.597
              B,__proto__,0.403
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.flows.length" do
      expect(diagram.flows.length).to eq(2)
    end

    it "retains diagram.flows 0 .source" do
      expect(diagram.flows[0].source).to eq("__proto__")
    end

    it "retains diagram.flows 0 .target" do
      expect(diagram.flows[0].target).to eq("A")
    end

    it "retains diagram.flows 0 .value" do
      expect(diagram.flows[0].value).to eq(0.597)
    end

    it "retains diagram.flows 1 .source" do
      expect(diagram.flows[1].source).to eq("B")
    end

    it "retains diagram.flows 1 .target" do
      expect(diagram.flows[1].target).to eq("__proto__")
    end

    it "retains diagram.flows 1 .value" do
      expect(diagram.flows[1].value).to eq(0.403)
    end
  end

  context "when calculates total flow" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
        A,D,5
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.total_flow" do
      expect(diagram.total_flow).to eq(35.0)
    end

    it "retains diagram.max_flow" do
      expect(diagram.max_flow).to eq(20.0)
    end

    it "retains diagram.min_flow" do
      expect(diagram.min_flow).to eq(5.0)
    end
  end

  context "when identifies source and sink nodes" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        Source,Middle,10
        Middle,Sink,10
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.source_nodes" do
      expect(diagram.source_nodes).to include("Source")
    end

    it "retains diagram.sink_nodes" do
      expect(diagram.sink_nodes).to include("Sink")
    end
  end

  context "when calculates node inflow and outflow" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        A,B,10
        B,C,7
        B,D,3
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.total_inflow B" do
      expect(diagram.total_inflow("B")).to eq(10.0)
    end

    it "retains diagram.total_outflow B" do
      expect(diagram.total_outflow("B")).to eq(10.0)
    end

    it "retains diagram.total_inflow A" do
      expect(diagram.total_inflow("A")).to eq(0.0)
    end

    it "retains diagram.total_outflow D" do
      expect(diagram.total_outflow("D")).to eq(0.0)
    end
  end

  context "when validates parsed sankey" do
    let(:source) do
      <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
      SANKEY
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.valid" do
      expect(diagram.valid?).to be true
    end
  end

  it "raises error on invalid syntax" do
    source = "invalid sankey syntax"

    expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
  end

  context "when raises error on missing header" do
    let(:source) do
      <<~SANKEY
        A,B,10
        B,C,20
      SANKEY
    end

    it "rejects the invalid source" do
      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end
  end
end
