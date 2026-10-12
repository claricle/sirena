# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart do
  let(:collision_source) do
    File.read("spec/mermaid/flowchart/current2-420bf58f.mmd")
  end

  def scene_for(source)
    graph = Sirena::Notation::Mermaid.parse(source).diagram
    described_class.new.call(graph)
  end

  def node(scene, id)
    scene.children.flat_map(&:children).find { |child| child.id == id }
  end

  it "uses Mermaid's compact box for the current2 node/subgraph collision" do
    collision = node(scene_for(collision_source), "B")

    expect([collision.width, collision.height])
      .to match([be_within(0.02).of(41.0625), 40.0])
  end

  it "preserves ordinary node padding when no empty subgraph reuses the id" do
    collision = node(scene_for(collision_source), "B")
    ordinary_source = collision_source.sub(/\n    subgraph B.*\z/m, "")
    ordinary = node(scene_for(ordinary_source), "B")

    expect([ordinary.width, ordinary.height])
      .to match([be_within(0.02).of(69.0625), 54.0])
    expect([collision.center_x, collision.center_y])
      .to eq([ordinary.center_x, ordinary.center_y])
  end
end
