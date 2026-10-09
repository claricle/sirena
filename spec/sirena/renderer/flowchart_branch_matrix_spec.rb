# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Flowchart do
  def label(text, x_coordinate, y_coordinate)
    Sirena::Layout::Flowchart::Label.new(
      text: text,
      x: x_coordinate,
      y: y_coordinate,
    )
  end

  def rectangle_node(node_id, labels: [], **attributes)
    Sirena::Layout::Flowchart::Node.new(
      id: node_id,
      shape_kind: "rect",
      shape_x: 0,
      shape_y: 0,
      shape_width: 40,
      shape_height: 20,
      labels: labels,
      children: [],
      **attributes,
    )
  end

  def default_theme
    Sirena::Theme::Registry.get(:default)
  end

  def scene(children:, edges: [])
    Sirena::Layout::Flowchart::Scene.new(
      id: "scene",
      width: 200,
      height: 120,
      view_box: "0 0 200 120",
      children: children,
      edges: edges,
    )
  end

  def render(children:, edges: [], theme: default_theme)
    renderer = described_class.new(theme: theme)
    renderer.render(scene(children: children, edges: edges))
  end

  def container_tree
    leaf = rectangle_node("leaf", labels: [label("Leaf", 20, 10)])
    inner = rectangle_node(
      "inner",
      container: true,
      cluster: true,
      corner_radius: 4,
      labels: [],
      children: [leaf],
    )
    [rectangle_node(
      "outer",
      container: true,
      cluster: true,
      corner_radius: 4,
      labels: [label("Outer", 20, 10)],
      children: [inner],
    )]
  end

  def shape_nodes
    kinds = %w[rect rounded circle rhombus hexagon mystery]
    kinds.map.with_index do |kind, index|
      rectangle_node(
        kind,
        shape_kind: kind,
        center_x: 20,
        center_y: 10,
        radius: 10,
        corner_radius: 6,
        shape_points: "0,10 20,0 40,10",
        labels: index.zero? ? [] : [label(kind, 20, 10)],
      )
    end
  end

  def styled_heads
    line = Sirena::Layout::Flowchart::Line.new(x1: 1, y1: 2, x2: 3, y2: 4)
    [
      Sirena::Layout::Flowchart::Head.new(
        shape: "arrow",
        points: "0,0 1,1 2,0",
      ),
      Sirena::Layout::Flowchart::Head.new(
        shape: "circle", x: 4, y: 5, radius: 2,
      ),
      Sirena::Layout::Flowchart::Head.new(shape: "cross", lines: [line]),
    ]
  end

  def styled_edges
    edge = Sirena::Layout::Flowchart::Edge
    [
      edge.new(
        id: "thick",
        path: "M 0 0 L 10 10",
        arrow_type: "thick_arrow",
        heads: styled_heads,
        labels: [label("edge", 5, 4)],
      ),
      edge.new(
        id: "dotted",
        path: "M 0 0 L 2 2",
        arrow_type: "dotted_line",
        heads: [],
        labels: [],
      ),
      edge.new(
        id: "hidden",
        path: "M 0 0 L 1 1",
        arrow_type: "invisible",
        heads: [],
        labels: [],
      ),
    ]
  end

  def edge_group(svg, name)
    svg.children.find { |child| child.id == "edge-#{name}" }
  end

  def first_path(group)
    group.children.grep(Sirena::Svg::Path).first
  end

  def edge_style_snapshot
    svg = render(children: [], edges: styled_edges, theme: Sirena::Theme.new)
    thick, dotted, hidden = %w[thick dotted hidden].map do |name|
      edge_group(svg, name)
    end
    [first_path(thick).stroke_width, first_path(dotted).stroke_dasharray,
     thick.children.map(&:class), hidden.children.first.stroke]
  end

  def node_outline_snapshot
    svg = render(children: shape_nodes)
    groups = svg.children.select { |child| child.id&.start_with?("node-") }
    groups.map do |group|
      [group.id, group.children.first.class, group.children.length]
    end
  end

  def expected_outlines
    [
      ["node-rect", Sirena::Svg::Rect, 1],
      ["node-rounded", Sirena::Svg::Rect, 2],
      ["node-circle", Sirena::Svg::Circle, 2],
      ["node-rhombus", Sirena::Svg::Polygon, 2],
      ["node-hexagon", Sirena::Svg::Polygon, 2],
      ["node-mystery", Sirena::Svg::Rect, 2],
    ]
  end

  def expected_edge_style
    ["3.5", "2",
     [Sirena::Svg::Path, Sirena::Svg::Polygon, Sirena::Svg::Circle,
      Sirena::Svg::Line, Sirena::Svg::Text],
     "none"]
  end

  it "recurses through containers without drawing them as nodes" do
    svg = render(children: container_tree)

    expect(svg.children.map(&:id))
      .to eq(%w[cluster-outer cluster-inner node-leaf])
  end

  it "dispatches every node outline while omitting an absent label" do
    expect(node_outline_snapshot).to eq(expected_outlines)
  end

  it "applies path styles and dispatches heads with theme fallbacks" do
    expect(edge_style_snapshot).to eq(expected_edge_style)
  end
end
