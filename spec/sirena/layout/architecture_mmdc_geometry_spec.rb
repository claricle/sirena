# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture do
  subject(:layout) { described_class.new }

  def service(id, group_id: nil)
    Sirena::Diagram::Architecture::Service.new(
      id: id, label: "#{id.upcase} with a rather long label",
      icon: "server", group_id: group_id
    )
  end

  def group(id, parent_id: nil)
    Sirena::Diagram::Architecture::Group.new(
      id: id, label: id.upcase, icon: "cloud", parent_id: parent_id,
    )
  end

  def edge(source, target, from, to)
    Sirena::Diagram::Architecture::Edge.new(
      from_id: source, to_id: target, from_position: from, to_position: to,
    )
  end

  def scene_for(services: [], groups: [], edges: [])
    layout.call(
      Sirena::Diagram::Architecture.new(
        services: services, groups: groups, edges: edges, junctions: [],
      ),
    )
  end

  def nodes(scene)
    scene.children.to_h { |node| [node.id, node] }
  end

  def centre(node)
    [node.x + (node.width / 2), node.y + (node.height / 2)]
  end

  # Sizes and offsets below are measured from mmdc
  # (spec/fixtures_mermaid/architecture/002).
  it "draws every service as an 80x80 box whatever its label says" do
    node = nodes(scene_for(services: [service("a")]))["a"]
    expect([node.width, node.height]).to eq([80, 80])
  end

  it "puts the service label under the box" do
    node = nodes(scene_for(services: [service("a")]))["a"]
    expect(node.labels.first.y).to be > node.y + node.height
  end

  it "places the target to the right when the source leaves on R" do
    scene = scene_for(services: [service("a"), service("b")],
                      edges: [edge("a", "b", "R", "L")])
    left, right = nodes(scene).values_at("a", "b").map { |n| centre(n) }
    expect([right[0] - left[0], right[1]]).to eq([201, left[1]])
  end

  it "places the target below when the source leaves on B" do
    scene = scene_for(services: [service("a"), service("b")],
                      edges: [edge("a", "b", "B", "T")])
    top, bottom = nodes(scene).values_at("a", "b").map { |n| centre(n) }
    expect([bottom[1] - top[1], bottom[0]]).to eq([201, top[0]])
  end

  it "draws an edge between facing sides as one straight segment" do
    scene = scene_for(services: [service("a"), service("b")],
                      edges: [edge("a", "b", "R", "L")])
    section = scene.edges.first.sections.first
    expect([section.bend_points, section.start_point.y,
            section.end_point.y]).to eq([[], 60, 60])
  end

  it "pads a group 42.5 on three sides and 17 more below its members" do
    scene = scene_for(services: [service("a", group_id: "g")],
                      groups: [group("g")])
    member, box = nodes(scene).values_at("a", "g")
    expect([member.x - box.x, member.y - box.y,
            box.width - member.width, box.height - member.height])
      .to eq([42.5, 42.5, 85, 102])
  end

  it "draws an isolated empty group as a 112x112 box beside the services" do
    scene = scene_for(services: [service("a")], groups: [group("g")])
    member, box = nodes(scene).values_at("a", "g")
    expect([box.width, box.height, box.x - (member.x + member.width)])
      .to eq([112, 112, 98])
  end

  it "keeps a group box off services that are not in it" do
    scene = scene_for(
      services: [service("in", group_id: "g"), service("out"),
                 service("also_in", group_id: "g")],
      groups: [group("g")],
      edges: [edge("in", "out", "R", "L"), edge("out", "also_in", "R", "L")],
    )
    box = nodes(scene)["g"]
    out = nodes(scene)["out"]
    overlap = box.x < out.x + out.width && out.x < box.x + box.width &&
              box.y < out.y + out.height && out.y < box.y + box.height
    expect(overlap).to be(false)
  end
end
