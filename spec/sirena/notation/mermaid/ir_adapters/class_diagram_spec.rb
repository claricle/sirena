# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/class_diagram"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::ClassDiagram do
  subject(:evidence) do
    graph = described_class.call(diagram)
    classes = graph.nodes.select { |node| node.role == "class" }
    members = graph.nodes.select do |node|
      member_roles.include?(node.role)
    end
    settings = graph.nodes.find { |node| node.role == "diagram_settings" }
    setting_values = graph.nodes.select do |node|
      node.parent_id == settings.id
    end.to_h { |node| [node.role, node.label] }
    relationship = graph.edges.first
    details = graph.nodes.select do |node|
      node.parent_id == relationship.parent_id
    end.to_h { |node| [node.role, node.label] }

    {
      valid: graph.valid?, graph: [graph.id, graph.label, graph.role],
      classes: classes.map { |node| [node.id, node.label] },
      members: members.map { |node| [node.role, node.label, node.parent_id] },
      edge: [relationship.source_id, relationship.target_id,
             relationship.label, relationship.properties.source_marker,
             relationship.properties.target_marker],
      details: details, settings: setting_values
    }
  end

  let(:member_roles) { %w[attribute operation] }

  let(:diagram) do
    parent = Sirena::Diagram::ClassEntity.new(
      id: "class_diagram", name: "Base", stereotype: "abstract",
      attributes: [Sirena::Diagram::ClassAttribute.new(
        name: "id", type: "Integer", visibility: "private", text: "-Integer id",
      )],
      class_methods: [Sirena::Diagram::ClassMethod.new(
        name: "find", parameters: "id", return_type: "Base",
        visibility: "public", text: "+find(id) Base"
      )]
    )
    child = Sirena::Diagram::ClassEntity.new(id: "Child", name: "Child")
    relationship = Sirena::Diagram::ClassRelationship.new(
      from_id: "Child", to_id: "class_diagram",
      relationship_type: "association", label: "owns",
      source_cardinality: "1", target_cardinality: "0..*",
      start_marker: "aggregation", end_marker: "inheritance", dashed: true
    )
    Sirena::Diagram::ClassDiagram.new(
      id: "class_diagram", title: "Domain", direction: "LR", theme: "dark",
      entities: [parent, child], relationships: [relationship]
    )
  end

  let(:expected_evidence) do
    {
      valid: true,
      graph: ["class_diagram_2", "Domain", "class_graph"],
      classes: [["class_diagram", "Base"], ["Child", "Child"]],
      members: [["attribute", "-Integer id", "class_diagram"],
                ["operation", "+find(id) : Base", "class_diagram"]],
      edge: ["Child", "class_diagram", "owns", "hollow_diamond", "triangle"],
      details: {
        "relationship_type" => "association",
        "source_cardinality" => "1", "target_cardinality" => "0..*",
        "source_marker" => "aggregation", "target_marker" => "inheritance",
        "dashed" => "true"
      },
      settings: {
        "diagram_identifier" => "class_diagram",
        "layout_direction" => "LR", "theme" => "dark"
      },
    }
  end

  it { is_expected.to eq(expected_evidence) }
end
