# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/c4"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::C4 do
  let(:ir) { described_class.call(c4_diagram) }

  it "produces valid collision-safe graph IR without geometry" do
    expect(graph_evidence).to eq([true, "c4_2", ir.items.length, true])
  end

  it "preserves ordered normalized boundaries and nested containment" do
    expect(boundary_evidence).to eq(expected_boundary_evidence)
  end

  it "preserves ordered normalized elements and complete semantics" do
    expect(element_evidence).to eq(expected_element_evidence)
  end

  it "resolves relationship endpoints, direction, labels, and technology" do
    expect(relationship_evidence).to eq(expected_relationship_evidence)
  end

  it "preserves title, level, layout intent, and diagram identity" do
    expect(settings_evidence).to eq(expected_settings_evidence)
  end

  def c4_diagram
    outer, inner = c4_boundaries
    actor, database, component = c4_elements(outer, inner)
    diagram_with(outer, inner, actor, database, component)
  end

  def c4_boundaries
    outer = boundary(
      "enterprise", "Company", "Enterprise_Boundary",
      link: "https://example.test/company", tags: "internal,owned"
    )
    inner = boundary(
      "system_scope", "Ordering", "System_Boundary",
      parent_id: outer.id, type_param: "software system"
    )
    [outer, inner]
  end

  def c4_elements(outer, inner)
    actor = c4_element(
      "c4", "Operator", "Person_Ext", outer.id, actor_attributes
    )
    database = c4_element(
      "relationship_0", "Orders", "ContainerDb", inner.id,
      database_attributes
    )
    component = c4_element(
      "relationship_details_0", "API", "Component", inner.id,
      component_attributes
    )
    [actor, database, component]
  end

  def boundary(id, label, type, parent_id: nil, **attributes)
    Sirena::Diagram::C4Boundary.new(
      id: id, label: label, boundary_type: type, parent_id: parent_id,
      **attributes
    )
  end

  def c4_element(id, label, type, boundary_id, attributes)
    Sirena::Diagram::C4Element.new(
      id: id, label: label, element_type: type, boundary_id: boundary_id,
      **attributes
    )
  end

  def diagram_with(outer, inner, actor, database, component)
    relationship = Sirena::Diagram::C4Relationship.new(
      from_id: actor.id, to_id: database.id, label: "Reads and writes",
      technology: "TLS", rel_type: "BiRel"
    )
    Sirena::Diagram::C4.new(
      id: "c4", title: "Ordering landscape", level: "Component",
      layout_config: "shapeInRow=3", boundaries: [outer, inner],
      elements: [actor, database, component], relationships: [relationship]
    )
  end

  def graph_evidence
    geometry_attributes = %i[x y width height]
    geometry_free = ir.items.all? do |item|
      geometry_attributes.none? { |name| item.respond_to?(name) }
    end
    [ir.valid?, ir.id, ir.items.map(&:id).uniq.length, geometry_free]
  end

  def boundary_evidence
    boundaries = ir.nodes.select { |node| boundary_roles.include?(node.role) }
    signature = boundaries.map do |node|
      [node.id, node.label, node.role, node.parent_id]
    end
    [signature, fields_for("enterprise"), fields_for("system_scope")]
  end

  def expected_boundary_evidence
    signature = [
      ["enterprise", "Company", "enterprise_boundary", nil],
      ["system_scope", "Ordering", "system_boundary", "enterprise"],
    ]
    enterprise = {
      "original_identifier" => "enterprise",
      "boundary_type" => "Enterprise_Boundary",
      "link" => "https://example.test/company", "tags" => "internal,owned"
    }
    system = {
      "original_identifier" => "system_scope",
      "boundary_type" => "System_Boundary",
      "parent_identifier" => "enterprise",
      "type_label" => "software system",
    }
    [signature, enterprise, system]
  end

  def element_evidence
    elements = ir.nodes.select { |node| fields_for(node.id)["element_type"] }
    signature = elements.map { |node| [node.id, node.role, node.parent_id] }
    [signature, fields_for("c4"), fields_for("relationship_0")]
  end

  def expected_element_evidence
    signature = [
      ["c4", "person", "enterprise"],
      ["relationship_0", "container_database", "system_scope"],
      ["relationship_details_0", "component", "system_scope"],
    ]
    actor = {
      "original_identifier" => "c4", "element_type" => "Person_Ext",
      "boundary_identifier" => "enterprise",
      "description" => "Manages orders", "sprite" => "person",
      "link" => "https://example.test/operator", "tags" => "external",
      "external" => "true"
    }
    database = {
      "original_identifier" => "relationship_0",
      "element_type" => "ContainerDb",
      "boundary_identifier" => "system_scope",
      "description" => "Stores orders", "technology" => "PostgreSQL",
      "external" => "false"
    }
    [signature, actor, database]
  end

  def relationship_evidence
    edge = ir.edges.fetch(0)
    edge_identity(edge) + edge_markers(edge) + edge_technology(edge)
  end

  def edge_identity(edge)
    [edge.id, edge.source_id, edge.target_id, edge.role, edge.label]
  end

  def edge_markers(edge)
    [edge.properties.source_marker, edge.properties.target_marker]
  end

  def edge_technology(edge)
    [fields_for(edge.parent_id)["technology"]]
  end

  def expected_relationship_evidence
    ["relationship_0_2", "c4", "relationship_0",
     "bidirectional_relationship", "Reads and writes", "arrow", "arrow",
     "TLS"]
  end

  def settings_evidence
    settings = ir.nodes.find { |node| node.role == "diagram_settings" }
    [ir.label, fields_for(settings.id)]
  end

  def expected_settings_evidence
    ["Ordering landscape",
     { "diagram_identifier" => "c4", "level" => "Component",
       "layout_intent" => "shapeInRow=3" }]
  end

  def boundary_roles
    %w[enterprise_boundary system_boundary boundary]
  end

  def actor_attributes
    {
      description: "Manages orders", sprite: "person",
      link: "https://example.test/operator", tags: "external", external: true
    }
  end

  def database_attributes
    { description: "Stores orders", technology: "PostgreSQL" }
  end

  def component_attributes
    { description: "Accepts requests", technology: "Ruby" }
  end

  def fields_for(parent_id)
    ir.nodes.select { |node| node.parent_id == parent_id }
      .select { |node| semantic_roles.include?(node.role) }
      .to_h { |node| [node.role, node.label] }
  end

  def semantic_roles
    %w[
      original_identifier boundary_type parent_identifier type_label link tags
      element_type boundary_identifier description technology sprite external
      relationship_type diagram_identifier level layout_intent
    ]
  end
end
