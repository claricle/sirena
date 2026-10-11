# frozen_string_literal: true

RSpec.describe Sirena::Layout::Flowchart, "#to_graph" do
  let(:builder) { FlowchartSceneBuilder }
  let(:line_height) { 16.0 * 1.5 }
  let(:text_width) do
    Sirena::TextMeasurement.measure_in(
      :trebuchet, "Laptop", font_size: 16.0
    )[:width]
  end

  it "pads a box 30 either side and 15 above and below a 1.5 line" do
    expect(builder.lone_node("rect", "Laptop")).to have_attributes(
      width: be_within(0.01).of(text_width + 60),
      height: be_within(0.01).of(line_height + 30),
    )
  end

  # Reference 001: node D "Laptop" is 109.265625 x 54, its label 49.27 x 24.
  it "sizes a box like mmdc's 16px reference" do
    expect(builder.lone_node("rect", "Laptop")).to have_attributes(
      width: be_within(1.0).of(109.27), height: 54.0,
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

  # Reference 130 (`a{{A <br> end}}`) draws a hexagon 74.54 wide and 63
  # high round a 26.39 x 48 label; reference 129, one line, is 54.76 wide.
  describe "a label of two lines" do
    let(:two_lines) { "A <br> end" }

    it "is as tall as two lines and as wide as the longer" do
      node = builder.lone_node("rect", two_lines)

      expect(node).to have_attributes(
        width: be_within(0.05).of(26.39 + 60),
        height: 2 * line_height + 30,
      )
    end

    it "widens a hexagon the way mmdc does" do
      expect(builder.lone_node("hexagon", two_lines)).to have_attributes(
        width: be_within(0.5).of(74.54), height: 63.0,
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
