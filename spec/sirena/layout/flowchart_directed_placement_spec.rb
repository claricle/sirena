# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart::DirectedPlacement do
  def scene_for(direction)
    diagram = Sirena::Diagram::Flowchart.new(direction: direction)
    %w[A B].each do |id|
      diagram.nodes << Sirena::Diagram::FlowchartNode.new(
        id: id, label: id, shape: "rect",
      )
    end
    diagram.edges << Sirena::Diagram::FlowchartEdge.new(
      source_id: "A", target_id: "B", arrow_type: "arrow",
    )
    Sirena::Layout::Flowchart.new.to_graph(diagram)
  end

  def nodes(scene)
    scene.children.to_h { |node| [node.id, node] }
  end

  it "ranks the target below its source for TD" do
    found = nodes(scene_for("TD"))

    expect(found["B"].y).to be >= found["A"].y + found["A"].height
  end

  it "ranks the target right of its source for LR" do
    found = nodes(scene_for("LR"))

    expect(found["B"].x).to be >= found["A"].x + found["A"].width
    expect(found["B"].y).to eq(found["A"].y)
  end

  it "ranks the target left of its source for RL" do
    found = nodes(scene_for("RL"))

    expect(found["A"].x).to be >= found["B"].x + found["B"].width
  end

  it "ranks the target above its source for BT" do
    found = nodes(scene_for("BT"))

    expect(found["A"].y).to be >= found["B"].y + found["B"].height
  end

  it "boxes a subgraph around its members with 20 points of padding" do
    xml = Sirena::Engine.new.render("flowchart TD\nsubgraph s [T]\nA --> B\nend\n")
    rects = xml.scan(/<rect[^>]*>/).map do |tag|
      %w[x y width height].map { |name| tag[/\s#{name}="(-?[\d.]+)"/, 1].to_f }
    end
    cluster = rects.max_by { |_, _, w, h| w * h }
    inner = rects.reject { |rect| rect == cluster }

    expect(inner.map { |x, _, w, _| x + w }.max).to be_within(1.0)
      .of(cluster[0] + cluster[2] - 20)
    expect(inner.map { |x, *| x }.min).to be_within(0.01).of(cluster[0] + 20)
  end

  it "places every node when a model repeats an id" do
    diagram = Sirena::Diagram::Flowchart.new(direction: "TD")
    diagram.nodes.push(
      Sirena::Diagram::FlowchartNode.new(id: "same", label: "First"),
      Sirena::Diagram::FlowchartNode.new(id: "same", label: "Second"),
    )

    scene = Sirena::Layout::Flowchart.new.to_graph(diagram)

    expect(scene.children.map(&:x)).to all(be_a(Float))
    expect(scene.children.map { |node| [node.x, node.y] }.uniq.size).to eq(2)
  end
end
