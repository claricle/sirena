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
  let(:compatible_summaries) do
    graph = Sirena::Notation::Mermaid::IRAdapter.call(:mindmap, diagram)
    [diagram, graph].map do |input|
      result = Sirena::Layout::Mindmap.new.call(input)
      [result.children.map { |node| [node.id, node.x, node.y, node.shape] },
       result.edges.map { |edge| [edge.source, edge.target, edge.path] }]
    end
  end

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

  it "renders all node shapes and labels inside node groups" do
    svg = renderer.render(scene)
    parts = svg.children.grep(Sirena::Svg::Group).flat_map(&:children)

    expect(parts.map { |part| part.class.name.split("::").last }.tally)
      .to eq("Circle" => 1, "Rect" => 1, "Polygon" => 1, "Path" => 1,
             "Text" => 4)
  end

  it "renders one link per child outside the node groups" do
    expect(renderer.render(scene).children.grep(Sirena::Svg::Path).length)
      .to eq(3)
  end

  it "wraps every node in an mmdc node group" do
    groups = renderer.render(scene).children.grep(Sirena::Svg::Group)

    expect(groups.map(&:class_name).uniq).to eq(["node mindmap-node"])
  end

  it "uses the Scene dimensions without renderer offsets" do
    svg = renderer.render(scene)

    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end

  it "lays out shared IR without changing direct Diagram compatibility" do
    expect(compatible_summaries.uniq.one?).to be(true)
  end

  it "ends a line that is followed by another with a space" do
    diagram = Sirena::Parser::Mindmap.new.parse("mindmap\n  a[one<br/>two]\n")
    scene = Sirena::Layout::Mindmap.new.call(diagram)
    xml = described_class.new.render(scene).to_xml

    expect(xml).to include(">one </tspan>")
  end
end
