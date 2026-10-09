# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::SankeyNode do
  it "uses the identifier when the label is blank" do
    node = described_class.new("source", "")

    expect(node.display_label).to eq("source")
  end

  it "requires a nonempty identifier" do
    expect(described_class.new("source")).to be_valid
    expect(described_class.new(nil)).not_to be_valid
    expect(described_class.new("")).not_to be_valid
  end
end

RSpec.describe Sirena::Diagram::SankeyFlow do
  it "coerces the value and accepts a positive flow" do
    flow = described_class.new("source", "target", "2.5")

    expect(flow.value).to eq(2.5)
    expect(flow).to be_valid
  end

  it "rejects missing endpoints and nonpositive values" do
    expect(described_class.new(nil, "target", 1)).not_to be_valid
    expect(described_class.new("", "target", 1)).not_to be_valid
    expect(described_class.new("source", nil, 1)).not_to be_valid
    expect(described_class.new("source", "", 1)).not_to be_valid
    expect(described_class.new("source", "target", 0)).not_to be_valid
  end

  it "identifies self-loops" do
    expect(described_class.new("same", "same", 1)).to be_self_loop
    expect(described_class.new("source", "target", 1)).not_to be_self_loop
  end
end

RSpec.describe Sirena::Diagram::Sankey do
  subject(:diagram) { described_class.new }

  let(:first_flow) { Sirena::Diagram::SankeyFlow.new("source", "middle", 4) }
  let(:second_flow) { Sirena::Diagram::SankeyFlow.new("middle", "sink", 3) }

  it "reports its diagram type" do
    expect(diagram.diagram_type).to eq(:sankey)
  end

  it "requires at least one valid flow" do
    expect(diagram).not_to be_valid

    diagram.flows << Sirena::Diagram::SankeyFlow.new("source", "sink", 0)
    expect(diagram).not_to be_valid

    diagram.flows = [first_flow]
    expect(diagram).to be_valid
  end

  it "combines unique flow and explicit node identifiers" do
    diagram.flows = [first_flow, second_flow]
    diagram.nodes << Sirena::Diagram::SankeyNode.new("source", "Source label")

    expect(diagram.all_node_ids).to eq(%w[source middle sink])
  end

  it "returns an explicit node or creates a default node" do
    explicit = Sirena::Diagram::SankeyNode.new("source", "Source label")
    diagram.nodes << explicit

    expect(diagram.node_by_id("source")).to equal(explicit)
    expect(diagram.node_by_id("new").display_label).to eq("new")
  end

  it "filters incoming and outgoing flows" do
    diagram.flows = [first_flow, second_flow]

    expect(diagram.flows_from("middle")).to eq([second_flow])
    expect(diagram.flows_to("middle")).to eq([first_flow])
  end

  it "calculates node totals and terminal nodes" do
    diagram.flows = [first_flow, second_flow]

    expect(diagram.total_outflow("middle")).to eq(3.0)
    expect(diagram.total_inflow("middle")).to eq(4.0)
    expect(diagram.source_nodes).to eq(["source"])
    expect(diagram.sink_nodes).to eq(["sink"])
  end

  it "calculates flow extrema and totals" do
    diagram.flows = [first_flow, second_flow]

    expect(diagram.total_flow).to eq(7.0)
    expect(diagram.max_flow).to eq(4.0)
    expect(diagram.min_flow).to eq(3.0)
  end

  it "uses zero extrema when empty" do
    expect(diagram.max_flow).to eq(0.0)
    expect(diagram.min_flow).to eq(0.0)
  end
end
