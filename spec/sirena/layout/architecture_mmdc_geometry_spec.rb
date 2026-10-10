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

  def pair_scene(from_side, to_side)
    scene_for(services: [service("a"), service("b")],
              edges: [edge("a", "b", from_side, to_side)])
  end

  def pair_centres(from_side, to_side)
    nodes(pair_scene(from_side, to_side)).values_at("a", "b").map do |node|
      centre(node)
    end
  end

  # Left, top, right and bottom room a box leaves around its member.
  def margins(member, box)
    [member.x - box.x, member.y - box.y,
     box.width - member.width, box.height - member.height]
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
    left, right = pair_centres("R", "L")
    expect([right[0] - left[0], right[1]]).to eq([201, left[1]])
  end

  it "places the target below when the source leaves on B" do
    top, bottom = pair_centres("B", "T")
    expect([bottom[1] - top[1], bottom[0]]).to eq([201, top[0]])
  end

  it "draws an edge between facing sides as one straight segment" do
    section = pair_scene("R", "L").edges.first.sections.first
    expect([section.bend_points, section.start_point.y,
            section.end_point.y]).to eq([[], 60, 60])
  end

  it "pads a group 42.5 on three sides and 17 more below its members" do
    scene = scene_for(services: [service("a", group_id: "g")],
                      groups: [group("g")])
    member, box = nodes(scene).values_at("a", "g")
    expect(margins(member, box)).to eq([42.5, 42.5, 85, 102])
  end

  it "draws an isolated empty group as a 112x112 box beside the services" do
    scene = scene_for(services: [service("a")], groups: [group("g")])
    member, box = nodes(scene).values_at("a", "g")
    expect([box.width, box.height, box.x - (member.x + member.width)])
      .to eq([112, 112, 98])
  end

  context "with a service between two members of a group" do
    let(:by_id) do
      nodes(scene_for(
              services: [service("in", group_id: "g"), service("out"),
                         service("also_in", group_id: "g")],
              groups: [group("g")],
              edges: [edge("in", "out", "R", "L"),
                      edge("out", "also_in", "R", "L")],
            ))
    end

    it "keeps the group box off services that are not in it" do
      expect(BoxOverlap.overlap?(by_id["g"], by_id["out"])).to be(false)
    end
  end
end
