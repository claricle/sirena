# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Sankey do
  subject(:diagram) { described_class.new }

  let(:first_flow) { Sirena::Diagram::SankeyFlow.new("source", "middle", 4) }
  let(:second_flow) { Sirena::Diagram::SankeyFlow.new("middle", "sink", 3) }

  describe Sirena::Diagram::SankeyNode do
    it "uses the identifier when the label is blank" do
      node = described_class.new("source", "")

      expect(node.display_label).to eq("source")
    end

    it "requires a nonempty identifier" do
      nodes = [described_class.new("source"), described_class.new(nil),
               described_class.new("")]
      expect(nodes.map(&:valid?)).to eq([true, false, false])
    end
  end

  describe Sirena::Diagram::SankeyFlow do
    it "coerces the value and accepts a positive flow" do
      flow = described_class.new("source", "target", "2.5")

      expect([flow.value, flow.valid?]).to eq([2.5, true])
    end

    it "rejects missing endpoints and nonpositive values" do
      flows = [[nil, "target", 1], ["", "target", 1],
               ["source", nil, 1], ["source", "", 1],
               ["source", "target", 0]]
      validity = flows.map { |args| described_class.new(*args).valid? }
      expect(validity).to eq([false, false, false, false, false])
    end

    it "identifies self-loops" do
      flows = [described_class.new("same", "same", 1),
               described_class.new("source", "target", 1)]
      expect(flows.map(&:self_loop?)).to eq([true, false])
    end
  end

  it "reports its diagram type" do
    expect(diagram.diagram_type).to eq(:sankey)
  end

  it "requires at least one valid flow" do
    states = [diagram.valid?, valid_after_flow(0), valid_after_flow(4)]

    expect(states).to eq([false, false, true])
  end

  def valid_after_flow(value)
    diagram.flows = [Sirena::Diagram::SankeyFlow.new("source", "sink", value)]
    diagram.valid?
  end

  it "combines unique flow and explicit node identifiers" do
    diagram.flows = [first_flow, second_flow]
    diagram.nodes << Sirena::Diagram::SankeyNode.new("source", "Source label")

    expect(diagram.all_node_ids).to eq(%w[source middle sink])
  end

  it "returns an explicit node or creates a default node" do
    explicit = Sirena::Diagram::SankeyNode.new("source", "Source label")
    diagram.nodes << explicit

    values = [diagram.node_by_id("source"),
              diagram.node_by_id("new").display_label]
    expect(values).to eq([explicit, "new"])
  end

  it "filters incoming and outgoing flows" do
    diagram.flows = [first_flow, second_flow]

    expect([diagram.flows_from("middle"), diagram.flows_to("middle")])
      .to eq([[second_flow], [first_flow]])
  end

  it "calculates node totals and terminal nodes" do
    diagram.flows = [first_flow, second_flow]

    values = [diagram.total_outflow("middle"), diagram.total_inflow("middle"),
              diagram.source_nodes, diagram.sink_nodes]
    expect(values).to eq([3.0, 4.0, ["source"], ["sink"]])
  end

  it "calculates flow extrema and totals" do
    diagram.flows = [first_flow, second_flow]

    expect([diagram.total_flow, diagram.max_flow, diagram.min_flow])
      .to eq([7.0, 4.0, 3.0])
  end

  it "uses zero extrema when empty" do
    expect([diagram.max_flow, diagram.min_flow]).to eq([0.0, 0.0])
  end
end
