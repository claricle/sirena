# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart, "node sizes" do
  def scene_for(shape, label: "Laptop")
    diagram = Sirena::Diagram::Flowchart.new(direction: "TD")
    diagram.nodes << Sirena::Diagram::FlowchartNode.new(
      id: "A", label: label, shape: shape,
    )
    described_class.new.to_graph(diagram).children.first
  end

  let(:text_width) { Sirena::TextMeasurement.measure("Laptop", font_size: 14.0)[:width] }

  it "pads a box 30 either side and 15 above and below a 1.5 line" do
    node = scene_for("rect")

    expect(node.width).to be_within(0.01).of(text_width + 60)
    expect(node.height).to be_within(0.01).of((14.0 * 1.5) + 30)
  end

  it "makes a diamond a square of label width + label height + 30" do
    node = scene_for("rhombus")

    expect(node.width).to be_within(0.01).of(text_width + (14.0 * 1.5) + 30)
    expect(node.height).to eq(node.width)
  end
end
