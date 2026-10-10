# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart, "#to_graph" do
  let(:builder) { FlowchartSceneBuilder }
  let(:line_height) { 14.0 * 1.5 }
  let(:text_width) do
    Sirena::TextMeasurement.measure("Laptop", font_size: 14.0)[:width]
  end

  it "pads a box 30 either side and 15 above and below a 1.5 line" do
    expect(builder.lone_node("rect", "Laptop")).to have_attributes(
      width: be_within(0.01).of(text_width + 60),
      height: be_within(0.01).of(line_height + 30),
    )
  end

  it "makes a diamond a square of label width + label height + 30" do
    node = builder.lone_node("rhombus", "Laptop")

    expect([node.width, node.height])
      .to all(be_within(0.01).of(text_width + line_height + 30))
  end

  # mmdc's extra width and height for each shape, measured on its output.
  {
    "rounded" => [30.0, 30.0],
    "hexagon" => [45.0, 15.0],
    "parallelogram" => [60.0, 15.0],
    "asymmetric" => [24.75, 15.0],
  }.each do |shape, (extra_width, extra_height)|
    it "sizes a #{shape} as label + #{extra_width} wide" do
      expect(builder.lone_node(shape, "Laptop")).to have_attributes(
        width: be_within(0.01).of(text_width + extra_width),
        height: be_within(0.01).of(line_height + extra_height),
      )
    end
  end

  it "makes a circle a square 15 wider than its label" do
    node = builder.lone_node("circle", "Laptop")

    expect([node.width, node.height])
      .to all(be_within(0.01).of(text_width + 15))
  end

  # Reference 132 (`a(((A)))`) draws an outer circle of r 17.21875 round a
  # 9.4375 label: a diameter 25 wider than the label. Reference 134, a label
  # 26.39 wide, draws r 25.6953125, which is 25 wider again.
  it "makes a double circle a square 25 wider than its label" do
    node = builder.lone_node("double_circle", "Laptop")

    expect([node.width, node.height])
      .to all(be_within(0.01).of(text_width + 25))
  end
end
