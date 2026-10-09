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
    actual = [scene.class, scene.children.map(&:class).uniq,
              scene.edges.map(&:class).uniq, scene.view_box]
    expected = [Sirena::Layout::Mindmap::Scene,
                [Sirena::Layout::Mindmap::Node],
                [Sirena::Layout::Mindmap::Edge],
                "0 0 #{scene.width} #{scene.height}"]
    expect(actual).to eq(expected)
  end

  it "includes framing in every node, link, and label coordinate" do
    root = scene.children.first
    link = scene.edges.first

    coordinates = [root.x, root.y, root.labels.first.x, root.labels.first.y]
    padding = Sirena::Layout::Mindmap::PADDING
    framing = coordinates.all? { |value| value >= padding }
    start_aligned = link.sections.first.start_point.x == root.center_x
    expect([framing, start_aligned, link.path.include?(root.center_x.to_s)])
      .to eq([true, true, true])
  end

  it "renders all node shapes, labels, and links" do
    svg = renderer.render(scene)

    types = [Sirena::Svg::Circle, Sirena::Svg::Rect, Sirena::Svg::Polygon,
             Sirena::Svg::Path, Sirena::Svg::Text]
    expect(types.map { |type| svg.children.grep(type).length })
      .to eq([1, 1, 1, 4, 4])
  end

  it "uses the Scene dimensions without renderer offsets" do
    svg = renderer.render(scene)

    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end
end
