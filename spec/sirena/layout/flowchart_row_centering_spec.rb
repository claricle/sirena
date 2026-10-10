# frozen_string_literal: true

# mmdc lines a chain of different-sized nodes up on their centres:
# `1Function-->2URL` has both centred on x 73.2.
RSpec.describe Sirena::Layout::Flowchart::RowCentering do
  def scene_for(direction, links)
    diagram = Sirena::Diagram::Flowchart.new(direction: direction)
    links.flatten.uniq.each do |id|
      diagram.nodes << Sirena::Diagram::FlowchartNode.new(
        id: id, label: id, shape: "rect",
      )
    end
    links.each do |from, to|
      diagram.edges << Sirena::Diagram::FlowchartEdge.new(
        source_id: from, target_id: to, arrow_type: "arrow",
      )
    end
    Sirena::Layout::Flowchart.new.to_graph(diagram).children.to_h { |n| [n.id, n] }
  end

  it "centres a narrower node under a wider one in TD" do
    found = scene_for("TD", [%w[WideNodeName Narrow]])

    expect(found["Narrow"].center_x).to be_within(0.01).of(found["WideNodeName"].center_x)
  end

  it "centres a shorter node beside a taller one in LR" do
    diagram = Sirena::Diagram::Flowchart.new(direction: "LR")
    diagram.nodes << Sirena::Diagram::FlowchartNode.new(id: "A", label: "one<br>two<br>three", shape: "rect")
    diagram.nodes << Sirena::Diagram::FlowchartNode.new(id: "B", label: "b", shape: "rect")
    diagram.edges << Sirena::Diagram::FlowchartEdge.new(source_id: "A", target_id: "B", arrow_type: "arrow")
    found = Sirena::Layout::Flowchart.new.to_graph(diagram).children.to_h { |n| [n.id, n] }

    expect(found["B"].center_y).to be_within(0.01).of(found["A"].center_y)
  end

  it "centres a parent over a row of two children" do
    found = scene_for("TD", [%w[Parent Left], %w[Parent Right]])
    row_centre = (found["Left"].x + found["Right"].x + found["Right"].width) / 2

    expect(found["Parent"].center_x).to be_within(0.01).of(row_centre)
  end
end
