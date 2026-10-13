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
  let(:link) { scene.edges.first }
  let(:compatible_summaries) do
    graph = Sirena::Notation::Mermaid::IRAdapter.call(:mindmap, diagram)
    [diagram, graph].map do |input|
      result = Sirena::Layout::Mindmap.new.call(input)
      [result.children.map { |node| [node.id, node.x, node.y, node.shape] },
       result.edges.map { |edge| [edge.source, edge.target, edge.path] }]
    end
  end

  it "returns typed final scene, node and edge classes" do
    actual = [scene.class, scene.children.map(&:class).uniq,
              scene.edges.map(&:class).uniq]
    expect(actual).to eq([Sirena::Layout::Mindmap::Scene,
                          [Sirena::Layout::Mindmap::Node],
                          [Sirena::Layout::Mindmap::Edge]])
  end

  it "sizes the view box to the final canvas" do
    expect(scene.view_box).to eq("0 0 #{scene.width} #{scene.height}")
  end

  it "includes framing in every node and label coordinate" do
    root = scene.children.first
    coordinates = [root.x, root.y, root.labels.first.x, root.labels.first.y]
    padding = Sirena::Layout::Mindmap::PADDING

    expect(coordinates.all? { |value| value >= padding }).to be(true)
  end

  it "insets the link start from the root centre" do
    root = scene.children.first
    start = link.sections.first.start_point
    centre_gap = Math.hypot(start.x - root.center_x,
                            start.y - (root.y + (root.height / 2)))

    expect(centre_gap.round(6)).to eq(Sirena::Layout::Mindmap::EDGE_INSET)
  end

  it "starts the link path at its start point" do
    start = link.sections.first.start_point

    expect(link.path.start_with?("M #{start.x} ")).to be(true)
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
