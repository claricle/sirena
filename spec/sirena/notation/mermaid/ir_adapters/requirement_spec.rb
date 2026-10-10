# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/requirement"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Requirement do
  def requirement
    Sirena::Diagram::RequirementNode.new(
      name: "requirement_graph", type: "functionalRequirement", id: "REQ-1",
      text: "Accept signed events", risk: "high", verifymethod: "test",
      classes: %w[critical audited]
    )
  end

  def element
    Sirena::Diagram::RequirementElement.new(
      name: "relationship_0", type: "service", docref: "ARCH-4",
      classes: ["external"]
    )
  end

  def relationship
    Sirena::Diagram::RequirementRelationship.new(
      source: "relationship_0", target: "requirement_graph",
      type: "satisfies"
    )
  end

  def inline_style
    Sirena::Diagram::RequirementStyle.new(
      target_ids: %w[requirement_graph relationship_0], fill: "#fee",
      stroke: "#900", stroke_width: "3px", properties: ["opacity:0.8"]
    )
  end

  def style_class
    Sirena::Diagram::RequirementClass.new(
      name: "critical", fill: "#fdd", stroke: "#800",
      stroke_width: "2px", properties: ["font-weight:bold"]
    )
  end

  def assignment
    Sirena::Diagram::RequirementClassAssignment.new(
      target_ids: ["requirement_graph"], class_names: %w[critical audited],
    )
  end
  let(:diagram) do
    Sirena::Diagram::Requirement.new(
      id: "requirement_graph", title: "Safety requirements",
      requirements: [requirement], elements: [element],
      relationships: [relationship], styles: [inline_style],
      classes: [style_class], class_assignments: [assignment],
      acc_title: "Accessible requirements",
      acc_description: "Requirement relationships"
    )
  end
  let(:ir) { described_class.call(diagram) }

  it "produces valid collision-safe graph IR with accessibility" do
    expect(accessibility_evidence).to eq(expected_accessibility_evidence)
  end

  it "preserves ordered requirement and element identity and semantics" do
    expect(entity_signature).to eq(expected_entity_signature)
  end

  it "preserves normalized, resolvable relationship semantics" do
    edge = ir.edges.fetch(0)
    expect([edge.id, edge.role, edge.source_id, edge.target_id])
      .to eq(["relationship_0_2", "satisfies", "relationship_0",
              "requirement_graph"])
  end

  it "preserves inline styles, class definitions, and assignments" do
    expect(style_signature).to eq(expected_style_signature)
  end

  def entity_signature
    entities.map do |node|
      [node.id, node.label, node.role, child_signature(node.id)]
    end
  end

  def accessibility_evidence
    [ir.valid?, ir.id, collision_free?, ir.accessibility_title,
     ir.accessibility_description]
  end

  def expected_accessibility_evidence
    [true, "requirement_graph_2", true, "Accessible requirements",
     "Requirement relationships"]
  end

  def collision_free?
    ir.nodes.map(&:id).uniq.length == ir.nodes.length
  end

  def entities
    roles = %w[requirement element]
    ir.nodes.select { |node| roles.include?(node.role) }
  end

  def child_signature(parent_id)
    ir.nodes.select { |node| node.parent_id == parent_id }
      .map { |node| [node.role, node.label] }
  end

  def expected_entity_signature
    [
      ["requirement_graph", "requirement_graph", "requirement",
       [["requirement_type", "functional_requirement"],
        ["external_identifier", "REQ-1"],
        ["description", "Accept signed events"], ["risk", "high"],
        ["verification_method", "test"],
        ["style_reference", "critical"],
        ["style_reference", "audited"]]],
      ["relationship_0", "relationship_0", "element",
       [["element_type", "service"], ["document_reference", "ARCH-4"],
        ["style_reference", "external"]]],
    ]
  end

  def style_signature
    roles = %w[inline_style style_class style_assignment]
    ir.nodes.select { |node| roles.include?(node.role) }
      .map { |node| [node.role, node.label, child_signature(node.id)] }
  end

  def expected_style_signature
    [
      ["inline_style", nil,
       [["target_reference", "requirement_graph"],
        ["target_reference", "relationship_0"], ["fill_color", "#fee"],
        ["stroke_color", "#900"], ["stroke_width", "3px"],
        ["style_property", "opacity:0.8"]]],
      ["style_class", "critical",
       [["fill_color", "#fdd"], ["stroke_color", "#800"],
        ["stroke_width", "2px"],
        ["style_property", "font-weight:bold"]]],
      ["style_assignment", nil,
       [["target_reference", "requirement_graph"],
        ["style_reference", "critical"],
        ["style_reference", "audited"]]],
    ]
  end
end
