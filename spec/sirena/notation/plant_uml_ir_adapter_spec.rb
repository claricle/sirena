# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::IRAdapter do
  include PlantUmlIrHelpers

  let(:diagram) { parse_class(feature_source) }
  let(:graph) { described_class.call(diagram) }

  def nodes(role)
    graph.nodes.select { |node| node.role == role }
  end

  it "emits a valid shared graph" do
    expect(graph).to be_a(Sirena::IR::Graph).and be_valid
  end

  it "names no notation in any role" do
    roles = (graph.nodes + graph.edges).filter_map(&:role)

    expect(roles.grep(/plantuml|puml|mermaid/)).to be_empty
  end

  it "makes each class a node of its kind" do
    expect(nodes("abstract_class").map(&:label)).to eq(["Shape"])
  end

  it "nests a class under the package it was declared in" do
    shape = nodes("abstract_class").first
    parent = graph.nodes.find { |node| node.id == shape.parent_id }

    expect(parent.label).to eq("Outer")
  end

  it "hangs members off their class in source order" do
    shape = nodes("abstract_class").first
    members = graph.nodes.select { |node| node.parent_id == shape.id }

    expect(members.select { |node| node.role == "method" }.map(&:label))
      .to eq(%w[area run])
  end

  it "makes a relation an edge from left to right with its markers" do
    edge = graph.edges.find { |item| item.role == "extension" }

    expect([edge.properties.source_marker, edge.properties.target_marker])
      .to eq(["extension", nil])
  end

  it "keeps the relation label on the edge" do
    labels = graph.edges.filter_map(&:label)

    expect(labels).to include("owns >", "uses")
  end

  it "attaches a note to its class with an edge" do
    links = graph.edges.select { |edge| edge.role == "note_link" }

    expect(links.size).to eq(2)
  end

  it "joins an association class to both ends and its owner" do
    roles = graph.edges.map(&:role)

    expect(roles.grep(/\Aassociation_/))
      .to eq(%w[association_end association_end association_owner])
  end
end
