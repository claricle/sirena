# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture do
  subject(:layout) { described_class.new }

  def service(id, label: id, group_id: nil)
    Sirena::Diagram::Architecture::Service.new(
      id: id, label: label, group_id: group_id,
    )
  end

  def edge(source, target, from: "R", to: "L", label: nil)
    Sirena::Diagram::Architecture::Edge.new(
      from_id: source, to_id: target, from_position: from,
      to_position: to, label: label
    )
  end

  def branch_scene
    group = Sirena::Diagram::Architecture::Group.new(id: "g")
    diagram = Sirena::Diagram::Architecture.new(
      groups: [group],
      services: [service("a", label: nil, group_id: "g"), service("b")],
      edges: [edge("a", "b", from: "T", to: "B", label: ""),
              edge("a", "missing")],
    )
    layout.call(diagram)
  end

  def branch_evidence
    scene = branch_scene
    nodes = scene.children.to_h { |node| [node.id, node] }
    [scene.edges.length, empty_branch_labels?(scene, nodes),
     declared_faces?(scene, nodes)]
  end

  def empty_branch_labels?(scene, nodes)
    [nodes["g"].labels, nodes["a"].labels, scene.edges[0].labels]
      .all?(&:empty?)
  end

  def declared_faces?(scene, nodes)
    section = scene.edges.fetch(0).sections.fetch(0)
    starts_on_top?(section, nodes["a"]) &&
      ends_on_bottom?(section, nodes["b"])
  end

  def starts_on_top?(section, node)
    section.start_point.y == node.y
  end

  def ends_on_bottom?(section, node)
    section.end_point.y == node.y + node.height
  end

  it "returns finite empty final geometry for an empty diagram" do
    scene = layout.call(Sirena::Diagram::Architecture.new)

    expect(scene).to have_attributes(
      width: 40.0, height: 40.0, view_box: "0 0 40 40",
      children: [], edges: []
    )
  end

  it "omits unresolved edges and empty labels while honoring declared faces" do
    expect(branch_evidence).to eq([1, true, true])
  end
end
