# frozen_string_literal: true

require "spec_helper"

module ClassDiagramLegacyPathHelpers
  module_function

  NODES = [
    { id: "A", x: 10, y: 20, width: 120, height: 80 },
    { id: "B", x: 210, y: 20, width: 120, height: 80 },
  ].freeze

  def render_edge(edge, renderer: Sirena::Renderer::ClassDiagram.new)
    graph = { id: "legacy", children: NODES, edges: [edge] }
    renderer.render(graph).children.find { |c| c.id == "rel-#{edge[:id]}" }
  end

  def mixed_edge(start_marker, end_marker, dashed: false)
    {
      id: "mixed", sources: ["A"], targets: ["B"],
      metadata: { start_marker: start_marker, end_marker: end_marker,
                  dashed: dashed }
    }
  end

  def labeled_edge(labels)
    { id: "lab", sources: ["A"], targets: ["B"], labels: labels }
  end

  def label_texts(group)
    group.children.grep(Sirena::Svg::Text)
      .map { |text| Array(text.content).join }
  end

  def polygon_fills(group)
    group.children.grep(Sirena::Svg::Polygon).map(&:fill)
  end

  def dashed_scene_path
    graph = { id: "d", children: NODES, edges: [dashed_dependency] }
    scene = Sirena::Layout::ClassDiagram.from_graph(graph)
    scene.edges.first.sections = [bent_section]
    scene
  end

  def dashed_dependency
    {
      id: "dep", sources: ["A"], targets: ["B"],
      metadata: { relationship_type: "dependency" }
    }
  end

  def bent_section
    point = Sirena::Layout::ClassDiagram::Point
    Sirena::Layout::ClassDiagram::Section.new(
      start_point: point.new(x: 100, y: 25),
      end_point: point.new(x: 200, y: 25),
      bend_points: [point.new(x: 150, y: 80)],
    )
  end
end

RSpec.describe Sirena::Renderer::ClassDiagram do
  let(:helpers) { ClassDiagramLegacyPathHelpers }
  let(:renderer) { described_class.new }

  describe "legacy Hash input without collections" do
    it "renders only the marker defs when :children is absent" do
      svg = renderer.render(id: "empty")
      expect(svg.children.map(&:id)).to eq(%w[defs])
    end

    it "renders no relationship groups when :edges is absent" do
      svg = renderer.render(id: "e", children: helpers::NODES)
      ids = svg.children.map { |child| child.id.to_s }
      expect(ids.grep(/\Arel-/)).to be_empty
    end

    it "drops an edge that names no endpoints" do
      expect(helpers.render_edge({ id: "bare" })).to be_nil
    end

    it "drops an edge whose graph has no children" do
      svg = renderer.render(id: "n", edges: [{ id: "x", sources: ["A"],
                                               targets: ["B"] }])
      expect(svg.children.map { |c| c.id.to_s }).not_to include("rel-x")
    end
  end

  describe "legacy node details" do
    it "renders a non-empty stereotype for a Hash node" do
      node = { id: "A", metadata: { stereotype: "interface" } }
      svg = renderer.render(id: "s", children: [node])
      texts = svg.children.grep(Sirena::Svg::Group).flat_map(&:children)
      expect(texts.grep(Sirena::Svg::Text).map { |t| t.content.join })
        .to include("«interface»")
    end
  end

  describe "released protected size hooks" do
    it "defaults the width to 800 without children" do
      expect(renderer.send(:calculate_width, {})).to eq(800)
    end

    it "defaults the height to 600 without children" do
      expect(renderer.send(:calculate_height, {})).to eq(600)
    end

    it "pads the widest sparse child by 40" do
      graph = { children: [{ x: 10 }, { width: 50 }] }
      expect(renderer.send(:calculate_width, graph)).to eq(200)
    end

    it "pads the tallest sparse child by 40" do
      graph = { children: [{ y: 10 }, { height: 50 }] }
      expect(renderer.send(:calculate_height, graph)).to eq(150)
    end

    it "pads an empty children list from the 800 default" do
      expect(renderer.send(:calculate_width, { children: [] })).to eq(840)
    end

    it "pads an empty children list from the 600 default" do
      expect(renderer.send(:calculate_height, { children: [] })).to eq(640)
    end
  end

  describe "mixed-marker legacy edges" do
    it "dashes the line when the edge is dashed" do
      group = helpers.render_edge(helpers.mixed_edge("composition", nil,
                                                     dashed: true))
      expect(group.children.grep(Sirena::Svg::Line).first.stroke_dasharray)
        .to eq("5,5")
    end

    it "leaves the line solid when the edge is not dashed" do
      group = helpers.render_edge(helpers.mixed_edge("composition", nil))
      expect(group.children.grep(Sirena::Svg::Line).first.stroke_dasharray)
        .to be_nil
    end

    it "fills hollow inheritance and solid composition ends" do
      group = helpers.render_edge(helpers.mixed_edge("inheritance",
                                                     "composition"))
      expect(helpers.polygon_fills(group)).to eq(%w[#ffffff #000000])
    end

    it "fills solid dependency and hollow aggregation ends" do
      group = helpers.render_edge(helpers.mixed_edge("dependency",
                                                     "aggregation"))
      expect(helpers.polygon_fills(group)).to eq(%w[#000000 #ffffff])
    end

    it "draws no marker for an unknown end" do
      group = helpers.render_edge(helpers.mixed_edge("unknown", nil))
      expect(helpers.polygon_fills(group)).to be_empty
    end

    it "draws a marker for an end marker alone" do
      group = helpers.render_edge(helpers.mixed_edge(nil, "composition"))
      expect(helpers.polygon_fills(group)).to eq(%w[#000000])
    end
  end

  describe "legacy edge labels" do
    it "renders a lone source cardinality" do
      edge = helpers.labeled_edge([{ text: "one", position: "source" }])
      expect(helpers.label_texts(helpers.render_edge(edge))).to eq(%w[one])
    end

    it "renders a lone middle label" do
      edge = helpers.labeled_edge([{ text: "owns" }])
      expect(helpers.label_texts(helpers.render_edge(edge))).to eq(%w[owns])
    end
  end

  describe "dashed typed Scene edge with bends" do
    it "dashes the bent path" do
      group = renderer.render(helpers.dashed_scene_path).children
        .find { |c| c.id == "rel-dep" }
      expect(group.children.grep(Sirena::Svg::Path).first.stroke_dasharray)
        .to eq("5,5")
    end
  end
end
