# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart::DirectedPlacement do
  let(:builder) { FlowchartSceneBuilder }
  let(:subgraph_source) { "flowchart TD\nsubgraph s [T]\nA --> B\nend\n" }

  {
    "TD" => [%w[A B], :y],
    "LR" => [%w[A B], :x],
    "RL" => [%w[B A], :x],
    "BT" => [%w[B A], :y],
  }.each do |direction, ((from, to), axis)|
    it "ranks a #{direction} link's target past its source on #{axis}" do
      found = builder.placed(direction, [%w[A B]])

      expect(builder.clearance(found[from], found[to], axis)).to be >= 0
    end
  end

  it "keeps a sideways link level" do
    found = builder.placed("LR", [%w[A B]])

    expect(found["B"].y).to eq(found["A"].y)
  end

  it "boxes a subgraph 8 points beside and 25 above and below its members" do
    expect(builder.cluster_margins(subgraph_source)).to match(
      [be_within(1.0).of(8), be_within(1.0).of(8),
       be_within(0.01).of(25), be_within(1.0).of(25)],
    )
  end

  # The SVG writes whole points, so a width not rounded up can leave less
  # than the 8 mmdc keeps beside the members.
  it "never leaves a member closer than 8 points to its subgraph box" do
    source = "flowchart TD\nsubgraph s\nA[Laptop computer]\nend\n"

    expect(builder.cluster_margins(source).first(2)).to all(be >= 8.0)
  end

  context "when a model repeats an id" do
    let(:scene) do
      diagram = Sirena::Diagram::Flowchart.new(direction: "TD")
      diagram.nodes.push(
        Sirena::Diagram::FlowchartNode.new(id: "same", label: "First"),
        Sirena::Diagram::FlowchartNode.new(id: "same", label: "Second"),
      )
      Sirena::Layout::Flowchart.new.to_graph(diagram)
    end

    it "places every node" do
      expect(scene.children.map(&:x)).to all(be_a(Float))
    end

    it "places the nodes apart" do
      expect(scene.children.map { |node| [node.x, node.y] }.uniq.size).to eq(2)
    end
  end
end
