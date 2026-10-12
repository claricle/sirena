# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/flowchart"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Flowchart do
  let(:collision_source) do
    File.read("spec/mermaid/flowchart/current2-420bf58f.mmd")
  end

  def collision_semantics(source)
    diagram = Sirena::Parser::Flowchart.new.parse(source)
    graph = described_class.call(diagram)
    node = collision_node(graph)
    graph.nodes.select { |candidate| candidate.parent_id == node.id }
      .select { |candidate| candidate.role == "subgraph_collision" }
      .map(&:label)
  end

  def collision_node(graph)
    graph.nodes.find do |candidate|
      candidate.role == "flow_node" && candidate.id == "B"
    end
  end

  it "preserves an empty-subgraph collision as node semantics" do
    expect(collision_semantics(collision_source)).to eq(["true"])
  end

  it "does not mark an ordinary node with the same source identity" do
    ordinary_source = collision_source.sub(/\n    subgraph B.*\z/m, "")

    expect(collision_semantics(ordinary_source)).to eq([])
  end
end
