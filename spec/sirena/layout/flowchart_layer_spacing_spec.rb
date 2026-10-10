# frozen_string_literal: true

# mmdc (dagre) gives an edge label its own rank, so a labelled link pushes
# its two nodes apart by the label's line box on top of the 50 between ranks:
# `graph TD;A--x|textNoSpace|B;` sits 74 apart at 16px, which is 50 + 24.
RSpec.describe Sirena::Layout::Flowchart::LayerSpacing do
  def scene_for(direction, label)
    diagram = Sirena::Diagram::Flowchart.new(direction: direction)
    %w[A B].each do |id|
      diagram.nodes << Sirena::Diagram::FlowchartNode.new(
        id: id, label: id, shape: "rect",
      )
    end
    diagram.edges << Sirena::Diagram::FlowchartEdge.new(
      source_id: "A", target_id: "B", arrow_type: "arrow", label: label,
    )
    Sirena::Layout::Flowchart.new.to_graph(diagram)
  end

  def gap(scene, axis)
    found = scene.children.to_h { |node| [node.id, node] }
    if axis == :y
      found["B"].y - (found["A"].y + found["A"].height)
    else
      found["B"].x - (found["A"].x + found["A"].width)
    end
  end

  it "leaves 50 between ranks when the link has no label" do
    expect(gap(scene_for("TD", nil), :y)).to be_within(0.01).of(50)
  end

  it "adds the label's 1.5 line height below a TD link" do
    scene = scene_for("TD", "textNoSpace")
    height = scene.edges.first.labels.first.height

    expect(gap(scene, :y)).to be_within(0.01).of(50 + (height * 1.5))
  end

  it "adds the label's width beside an LR link" do
    scene = scene_for("LR", "textNoSpace")
    width = scene.edges.first.labels.first.width

    expect(gap(scene, :x)).to be_within(0.01).of(50 + width)
  end
end
