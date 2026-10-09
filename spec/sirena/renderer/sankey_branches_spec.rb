# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sankey do
  def label(text, x, y)
    Sirena::Layout::Sankey::Label.new(text: text, x: x, y: y)
  end

  def scene(title: nil, flows: [])
    node = Sirena::Layout::Sankey::Node.new(
      id: "a", layer: 0, x: 10, y: 20, width: 30, height: 40,
      corner_radius: 3, label: label("Node A", 25, 45), inflow: 0,
      outflow: 4
    )
    Sirena::Layout::Sankey::Scene.new(
      id: "sankey", width: 200, height: 120, view_box: "0 0 200 120",
      title: title, nodes: [node], flows: flows
    )
  end

  def flow(id:, label: nil, self_loop: false, colour_index: 0)
    Sirena::Layout::Sankey::Flow.new(
      id: id, source: "a", target: "b", value: 4, width: 20,
      source_x: 40, source_y: 40, target_x: 150, target_y: 40,
      path: "M 40 30 L 150 30 L 150 50 L 40 50 Z", label: label,
      colour_index: colour_index, self_loop: self_loop
    )
  end

  it "renders title, labelled and unlabelled flows, and omits self-loops" do
    flows = [
      flow(id: "labelled", label: label("4", 95, 40), colour_index: 1),
      flow(id: "plain", colour_index: 3),
      flow(id: "loop", self_loop: true),
    ]
    xml = described_class.new(theme: Sirena::Theme.new)
      .render(scene(title: label("Flows", 100, 15), flows: flows)).to_xml

    expect(xml.scan("<path").size).to eq(2)
    expect(xml).to include("Flows", ">4</text>", "#ED7D31", "#FFC000")
    expect(xml).to include('fill="#2E86AB"', 'stroke="#1A5276"')
    expect(xml).to include('font-family="Arial, sans-serif"')
  end

  it "uses theme node colors and typography and omits an absent title" do
    theme = Sirena::Theme.new(
      colors: Sirena::Theme::ColorPalette.new(
        node_fill: "#010203", node_stroke: "#040506",
        label_text: "#070809"
      ),
      typography: Sirena::Theme::Typography.new(
        font_family: "Example Sans", font_size_small: 13,
        font_size_large: 21
      ),
    )
    xml = described_class.new(theme: theme)
      .render(scene).to_xml

    expect(xml).to include('fill="#010203"', 'stroke="#040506"')
    expect(xml).to include('fill="#FFFFFF"', 'font-family="Example Sans"')
    expect(xml).not_to include("Themed")
  end
end
