# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence::IRAdapter do
  include PlantUmlSequenceIrHelpers

  let(:graph) { described_class.call(parse_sequence(sequence_feature_source)) }

  def nodes(*roles)
    graph.nodes.select { |node| roles.include?(node.role) }
  end

  it "emits a valid shared graph" do
    expect(graph).to be_a(Sirena::IR::Graph).and be_valid
  end

  it "names no notation in any role" do
    roles = (graph.nodes + graph.edges).filter_map(&:role)

    expect(roles.grep(/plantuml|puml|mermaid/)).to be_empty
  end

  it "makes each participant a node of its kind" do
    expect(nodes("actor", "boundary", "queue").map(&:label))
      .to eq(["Bob", "B1", "Q1"])
  end

  it "makes a message an edge from sender to receiver" do
    edge = graph.edges.find { |item| item.role == "message" }
    ids = graph.nodes.to_h { |node| [node.id, node.label] }

    expect([ids[edge.source_id], ids[edge.target_id]]).to eq(%w[Alice Bob])
  end

  it "keeps the dashed message's marker off the solid one" do
    markers = graph.edges.select { |item| item.role == "message" }
      .map { |item| item.properties.target_marker }

    expect(markers.first(3)).to eq(%w[filled filled open])
  end

  it "keeps messages, notes and blocks in source order" do
    roles = nodes("message", "note", "divider", "fragment").map(&:role)

    expect(roles.first(4)).to eq(%w[note message note message])
  end

  it "gives a message with no participant at one end an open end" do
    expect(nodes("open_end").size).to eq(4)
  end

  it "carries autonumber on the message" do
    numbers = graph.nodes.select { |node| node.role == "number" }

    expect(numbers.map(&:label)).to eq(%w[1 5])
  end
end
