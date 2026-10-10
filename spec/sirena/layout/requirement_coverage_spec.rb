# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Requirement do
  subject(:layout) { described_class.new }

  include LayoutIrShorthand

  def requirement(name, **attributes)
    Sirena::Diagram::RequirementNode.new(name: name, **attributes)
  end

  def relationship(source, target, type: "satisfies")
    Sirena::Diagram::RequirementRelationship.new(
      source: source, target: target, type: type,
    )
  end

  def diagram(requirements:, relationships: [])
    Sirena::Diagram::Requirement.new(
      requirements: requirements, relationships: relationships,
    )
  end

  it "omits absent requirement properties" do
    scene = layout.call(diagram(requirements: [requirement("minimal")]))

    expect(scene.children.first.labels.map(&:text))
      .to eq(["<<Requirement>>", "minimal"])
  end

  it "draws an unlabeled relationship without label geometry" do
    source = requirement("source")
    target = requirement("target")
    scene = layout.call(
      diagram(
        requirements: [source, target],
        relationships: [relationship("source", "target", type: nil)],
      ),
    )

    expect(scene.edges.first)
      .to have_attributes(labels: [], label_background: nil)
  end

  it "places cyclic dependencies together after bounded resolution" do
    requirements = [requirement("first"), requirement("second")]
    relationships = [relationship("first", "second"),
                     relationship("second", "first")]
    nodes = layout.call(
      diagram(requirements: requirements, relationships: relationships),
    ).children

    expect(nodes.map(&:y).uniq.one?).to be(true)
  end

  it "keeps an overlong word intact" do
    word = "unbreakable" * 30
    node = layout.call(
      diagram(requirements: [requirement("long", text: word)]),
    ).children.first

    expect(node.labels.map(&:text)).to include(word)
  end

  it "uses default typography when the injected theme has none" do
    scene = layout.call(
      diagram(requirements: [requirement("plain", id: "R-1")]),
      theme: Sirena::Theme.new,
    )
    property = scene.children.first.labels.find { |label| label.role == "property" }

    expect(property.font_size)
      .to eq(Sirena::Theme::Registry.get(:default).typography.font_size_small)
  end

  it "ignores an IR relationship whose endpoint is absent" do
    graph = ir_graph(
      id: "requirements",
      nodes: [ir_node(id: "present", label: "Present", role: "requirement")],
      edges: [ir_edge(id: "missing", source_id: "present",
                      target_id: "absent", role: "satisfies")],
    )

    expect(layout.build_graph(graph)[:relationships]).to be_empty
  end
end
