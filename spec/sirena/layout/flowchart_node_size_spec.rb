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

  # mmdc's extra width and height for each shape, measured on its output.
  {
    "rounded" => [30.0, 30.0],
    "hexagon" => [45.0, 15.0],
    "parallelogram" => [60.0, 15.0],
    "asymmetric" => [24.75, 15.0],
  }.each do |shape, (extra_width, extra_height)|
    it "sizes a #{shape} as label + #{extra_width} wide" do
      node = scene_for(shape)

      expect(node.width).to be_within(0.01).of(text_width + extra_width)
      expect(node.height).to be_within(0.01).of((14.0 * 1.5) + extra_height)
    end
  end

  it "makes a circle a square 15 wider than its label" do
    node = scene_for("circle")

    expect(node.width).to be_within(0.01).of(text_width + 15)
    expect(node.height).to eq(node.width)
  end
end
