# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture do
  subject(:scene) do
    described_class.new.call(
      Sirena::Diagram::Architecture.new(
        services: services, groups: groups, edges: edges, junctions: [],
      ),
    )
  end

  let(:arch) { Sirena::Diagram::Architecture }
  let(:groups) do
    %w[left right].map do |id|
      arch::Group.new(id: id, label: id, icon: "cloud")
    end
  end
  # "tail" in the left group is joined to "head" in the right group; the
  # right group also holds a chain that would drag its box over the left.
  let(:services) do
    [["a", "left"], ["tail", "left"], ["head", "right"], ["c", "right"],
     ["d", "right"]].map do |id, group|
      arch::Service.new(id: id, label: id, icon: "server", group_id: group)
    end
  end
  let(:edges) do
    [["a", "tail", "R", "L"], ["tail", "head", "R", "L"],
     ["head", "c", "B", "T"], ["c", "d", "L", "R"]].map do |from, to, from_side, to_side|
      arch::Edge.new(from_id: from, to_id: to, from_position: from_side,
                     to_position: to_side)
    end
  end
  let(:by_id) { scene.children.to_h { |node| [node.id, node] } }

  def overlap?(first, second)
    first.x < second.x + second.width && second.x < first.x + first.width &&
      first.y < second.y + second.height && second.y < first.y + first.height
  end

  it "keeps the two group boxes apart" do
    expect(overlap?(by_id["left"], by_id["right"])).to be(false)
  end

  it "keeps the group joined on R to the left of the other" do
    expect(by_id["left"].x + by_id["left"].width)
      .to be <= by_id["right"].x
  end

  it "keeps every service inside its own group box only" do
    expect(overlap?(by_id["d"], by_id["left"])).to be(false)
  end
end
