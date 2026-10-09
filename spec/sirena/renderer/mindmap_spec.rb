# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/mindmap"
require "sirena/layout/mindmap"
require "sirena/renderer/mindmap"

RSpec.describe Sirena::Renderer::Mindmap do
  subject(:renderer) { described_class.new }

  let(:source) do
    <<~MERMAID
      mindmap
        root((Root))
          square[Square]
          cloud)Cloud(
          hex{{Hex}}
    MERMAID
  end
  let(:diagram) { Sirena::Parser::Mindmap.new.parse(source) }
  let(:scene) { Sirena::Layout::Mindmap.new.call(diagram) }

  it "returns typed final canvas geometry" do
    expect(scene).to be_a(Sirena::Layout::Mindmap::Scene)
    expect(scene.children).to all(be_a(Sirena::Layout::Mindmap::Node))
    expect(scene.edges).to all(be_a(Sirena::Layout::Mindmap::Edge))
    expect(scene.view_box).to eq("0 0 #{scene.width} #{scene.height}")
  end

  it "includes framing in every node, link, and label coordinate" do
    root = scene.children.first
    link = scene.edges.first

    expect([root.x, root.y, root.labels.first.x, root.labels.first.y])
      .to all(be >= Sirena::Layout::Mindmap::PADDING)
    expect(link.sections.first.start_point.x).to eq(root.center_x)
    expect(link.path).to include(root.center_x.to_s)
  end

  it "renders all node shapes, labels, and links" do
    svg = renderer.render(scene)

    expect(svg.children.grep(Sirena::Svg::Circle).length).to eq(1)
    expect(svg.children.grep(Sirena::Svg::Rect).length).to eq(1)
    expect(svg.children.grep(Sirena::Svg::Polygon).length).to eq(1)
    expect(svg.children.grep(Sirena::Svg::Path).length).to eq(4)
    expect(svg.children.grep(Sirena::Svg::Text).length).to eq(4)
  end

  it "uses the Scene dimensions without renderer offsets" do
    svg = renderer.render(scene)

    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end
end
