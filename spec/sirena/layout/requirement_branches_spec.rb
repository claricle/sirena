# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Requirement do
  subject(:layout) { described_class.new }

  def requirement(name, **attributes)
    Sirena::Diagram::RequirementNode.new({ name: name }.merge(attributes))
  end

  def relationship(source, target, type: nil)
    Sirena::Diagram::RequirementRelationship.new(
      source: source, target: target, type: type,
    )
  end

  def sparse_scene
    diagram = Sirena::Diagram::Requirement.new(
      requirements: [requirement("Policy", type: "custom")],
      elements: [Sirena::Diagram::RequirementElement.new(name: "Gateway")],
      relationships: [relationship("Gateway", "Policy")],
    )
    layout.call(diagram)
  end

  def sparse_evidence
    scene = sparse_scene
    [node_labels(scene, "Policy"), node_labels(scene, "Gateway"),
     *edge_decoration(scene)]
  end

  def node_labels(scene, id)
    scene.children.find { |node| node.id == id }.labels.map(&:text)
  end

  def edge_decoration(scene)
    edge = scene.edges.fetch(0)
    [edge.labels, edge.label_background]
  end

  def cyclic_scene
    diagram = Sirena::Diagram::Requirement.new(
      requirements: [requirement("A"), requirement("B")],
      relationships: [relationship("A", "B", type: "derives"),
                      relationship("B", "A", type: "derives")],
    )
    layout.call(diagram)
  end

  def cyclic_evidence
    scene = cyclic_scene
    ids = scene.children.map(&:id).sort
    edges = scene.edges.map { |item| [item.source, item.target] }.sort
    [ids, scene.children.map(&:y).uniq.length, edges]
  end

  def wrapped_text_labels
    text = Array.new(24, "verification").join(" ")
    diagram = Sirena::Diagram::Requirement.new(
      requirements: [requirement("Wrapped", text: text)],
    )
    node = layout.call(diagram).children.fetch(0)
    node.labels.select { |label| label.role == "property" }
  end

  it "returns finite empty final geometry for an empty diagram" do
    scene = layout.call(Sirena::Diagram::Requirement.new)

    expect(scene).to have_attributes(
      width: 20.0, height: 40.0, view_box: "0 0 20 40",
      children: [], edges: []
    )
  end

  it "renders sparse custom entities without placeholder details" do
    expect(sparse_evidence)
      .to eq([["<<custom>>", "Policy"], ["<<Element>>", "Gateway"], [], nil])
  end

  it "falls cyclic dependencies back to a renderable level" do
    expect(cyclic_evidence).to eq([%w[A B], 1, [%w[A B], %w[B A]]])
  end

  it "wraps long requirement text into separately positioned labels" do
    labels = wrapped_text_labels
    expect([labels.length > 2, labels.map(&:y)])
      .to eq([true, labels.map(&:y).sort])
  end
end
