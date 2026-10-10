# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/er_diagram"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::ErDiagram do
  let(:ir) { described_class.call(diagram) }

  it "produces valid collision-safe graph IR without layout geometry" do
    expect(graph_evidence).to eq([true, "er_diagram_2", true, true, true])
  end

  it "preserves ordered entities, identity, attributes, and details" do
    expect(entity_evidence).to eq(expected_entity_evidence)
  end

  it "keeps value-equal entity instances distinct" do
    expect(value_equal_entity_ids).to eq(%w[duplicate duplicate_2])
  end

  it "does not mutate a source without initialized class definitions" do
    expect(pristine_source_unchanged?).to be(true)
  end

  it "preserves repeated style roles and ordered class declarations" do
    expect(style_evidence).to eq(expected_style_evidence)
  end

  it "preserves ordered relationship roles, cardinalities, and labels" do
    expect(relationship_evidence).to eq(expected_relationship_evidence)
  end

  it "preserves diagram identity, title, direction, and theme intent" do
    expect(metadata_evidence).to eq(expected_metadata_evidence)
  end

  def value_equal_entity_ids
    entity = Sirena::Diagram::ErEntity.new(id: "duplicate", name: "Same")
    source = Sirena::Diagram::ErDiagram.new(
      entities: [entity, Marshal.load(Marshal.dump(entity))],
    )
    graph = described_class.call(source)
    graph.nodes.select { |node| node.role == "entity" }.map(&:id)
  end

  def pristine_source_unchanged?
    source = Sirena::Diagram::ErDiagram.new
    before = Marshal.dump(source)
    described_class.call(source)
    Marshal.dump(source) == before
  end

  def diagram
    value = Sirena::Diagram::ErDiagram.new(
      id: "er_diagram", title: "Commerce model", direction: "LR",
      theme: "forest", entities: [customer, order],
      relationships: relationships
    )
    value.add_class_def("primary", "fill:red")
    value.add_class_def("audited", "stroke:blue")
    value
  end

  def customer
    Sirena::Diagram::ErEntity.new(
      id: "er_diagram", name: "Customer",
      classes: %w[primary audited primary],
      attributes: [customer_id, customer_email]
    )
  end

  def customer_id
    Sirena::Diagram::ErAttribute.new(
      name: "id", attribute_type: "int", key_type: "PK", note: "generated",
    )
  end

  def customer_email
    Sirena::Diagram::ErAttribute.new(
      name: "email", attribute_type: "string", key_type: "UK",
    )
  end

  def order
    Sirena::Diagram::ErEntity.new(
      id: "relationship_0", name: "Order",
      classes: ["audited"],
      attributes: [Sirena::Diagram::ErAttribute.new(
        name: "customer_id", attribute_type: "int", key_type: "FK",
      )]
    )
  end

  def relationships
    [
      relationship(%w[er_diagram relationship_0 identifying one zero_or_more],
                   "places"),
      relationship(
        %w[relationship_0 er_diagram non-identifying zero_or_one one_or_more],
        "belongs to",
      ),
    ]
  end

  def relationship(values, label)
    source, target, type, from_cardinality, to_cardinality = values
    Sirena::Diagram::ErRelationship.new(
      from_id: source, to_id: target, relationship_type: type,
      cardinality_from: from_cardinality, cardinality_to: to_cardinality,
      label: label
    )
  end

  def graph_evidence
    source = diagram
    before = Marshal.dump(source)
    graph = described_class.call(source)
    [graph.valid?, graph.id, collision_free?(graph), geometry_free?(graph),
     Marshal.dump(source) == before]
  end

  def collision_free?(graph)
    identifiers = [graph.id, *graph.items.map(&:id)]
    identifiers.uniq.length == identifiers.length
  end

  def geometry_free?(graph)
    geometry = %i[x y width height sections bend_points]
    graph.items.all? do |item|
      geometry.none? { |name| item.respond_to?(name) }
    end
  end

  def entity_evidence
    [entity_nodes.map { |node| [node.id, node.label, node.role] },
     attribute_nodes.map { |node| attribute_signature(node) }]
  end

  def expected_entity_evidence
    [[
      ["er_diagram", "Customer", "entity"],
      ["relationship_0", "Order", "entity"],
    ], [
      ["er_diagram", "id", "int", "PK", "generated", "0"],
      ["er_diagram", "email", "string", "UK", nil, "1"],
      ["relationship_0", "customer_id", "int", "FK", nil, "0"],
    ]]
  end

  def attribute_signature(node)
    fields = fields_for(node.id)
    [node.parent_id, node.label, fields["attribute_type"], fields["key_type"],
     fields["note"], fields["sequence_index"]]
  end

  def style_evidence
    references = entity_nodes.map do |node|
      [node.id, children_with_role(node.id, "style_reference").map(&:label)]
    end
    definitions = nodes_with_role("style_class").map do |node|
      [node.label, fields_for(node.id)["style_declaration"]]
    end
    [references, definitions]
  end

  def expected_style_evidence
    [[
      ["er_diagram", %w[primary audited primary]],
      ["relationship_0", ["audited"]],
    ], [["primary", "fill:red"], ["audited", "stroke:blue"]]]
  end

  def relationship_evidence
    ir.edges.map { |edge| relationship_signature(edge) }
  end

  def relationship_signature(edge)
    fields = fields_for(edge.parent_id)
    [edge.id, edge.source_id, edge.target_id, edge.role, edge.label,
     edge.properties.source_marker, edge.properties.target_marker,
     fields["relationship_type"]]
  end

  def expected_relationship_evidence
    [
      ["relationship_0_2", "er_diagram", "relationship_0",
       "identifying_relationship", "places", "one", "zero_or_more",
       "identifying"],
      ["relationship_1", "relationship_0", "er_diagram",
       "non_identifying_relationship", "belongs to", "zero_or_one",
       "one_or_more", "non-identifying"],
    ]
  end

  def metadata_evidence
    settings = nodes_with_role("diagram_settings").fetch(0)
    [ir.label, fields_for(settings.id)]
  end

  def expected_metadata_evidence
    ["Commerce model",
     { "diagram_identifier" => "er_diagram", "layout_direction" => "LR",
       "theme_reference" => "forest" }]
  end

  def entity_nodes
    nodes_with_role("entity")
  end

  def attribute_nodes
    nodes_with_role("attribute")
  end

  def nodes_with_role(role)
    ir.nodes.select { |node| node.role == role }
  end

  def children_with_role(parent_id, role)
    ir.nodes.select { |node| node.parent_id == parent_id && node.role == role }
  end

  def fields_for(parent_id)
    ir.nodes.select { |node| node.parent_id == parent_id }
      .select { |node| semantic_role?(node.role) }
      .to_h { |node| [node.role, node.label] }
  end

  def semantic_role?(role)
    role.end_with?("identifier", "index", "type", "cardinality") ||
      %w[note style_declaration layout_direction theme_reference].include?(role)
  end
end
