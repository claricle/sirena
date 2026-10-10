# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture do
  subject(:layout) { described_class.new }

  def service(id, group_id: nil)
    Sirena::Diagram::Architecture::Service.new(
      id: id, label: id.upcase, icon: "server", group_id: group_id,
    )
  end

  def junction(id, group_id: nil)
    Sirena::Diagram::Architecture::Junction.new(id: id, group_id: group_id)
  end

  def group(id, parent_id: nil)
    Sirena::Diagram::Architecture::Group.new(
      id: id, label: id.upcase, icon: "cloud", parent_id: parent_id,
    )
  end

  def edge(source, target, from: "R", to: "L", label: nil)
    Sirena::Diagram::Architecture::Edge.new(
      from_id: source, to_id: target, from_position: from,
      to_position: to, label: label
    )
  end

  def diagram(services: [], junctions: [], groups: [], edges: [])
    Sirena::Diagram::Architecture.new(
      services: services, junctions: junctions, groups: groups, edges: edges,
    )
  end

  def overlap?(left, right)
    intervals_overlap?(left.x, left.width, right.x, right.width) &&
      intervals_overlap?(left.y, left.height, right.y, right.height)
  end

  def intervals_overlap?(left_position, left_size, right_position, right_size)
    left_position < right_position + right_size &&
      right_position < left_position + left_size
  end

  def contains?(outer, inner)
    interval_contains?(outer.x, outer.width, inner.x, inner.width) &&
      interval_contains?(outer.y, outer.height, inner.y, inner.height)
  end

  def interval_contains?(outer_position, outer_size, inner_position, inner_size)
    outer_position <= inner_position &&
      outer_position + outer_size >= inner_position + inner_size
  end

  def points(edge)
    section = edge.sections.first
    [section.start_point, *section.bend_points, section.end_point]
  end

  def segment_crosses?(node, first, last)
    (0..200).any? do |index|
      ratio = index / 200.0
      point_inside?(node, *point_on_segment(first, last, ratio))
    end
  end

  def point_on_segment(first, last, ratio)
    [first.x + ((last.x - first.x) * ratio),
     first.y + ((last.y - first.y) * ratio)]
  end

  def point_inside?(node, x_coord, y_coord)
    x_coord > node.x && x_coord < node.x + node.width &&
      y_coord > node.y && y_coord < node.y + node.height
  end

  def routed_scene
    layout.call(
      diagram(services: [service("a"), service("b")],
              edges: [edge("a", "b", label: "HTTP")]),
    )
  end

  def junction_scene
    layout.call(
      diagram(services: [service("a")], junctions: [junction("mid")],
              edges: [edge("a", "mid")]),
    )
  end

  def junction_route_scene
    layout.call(
      diagram(services: [service("left"), service("right")],
              junctions: [junction("mid")],
              edges: [edge("left", "mid"), edge("mid", "right")]),
    )
  end

  def mixed_group_nodes
    layout.call(
      diagram(services: [service("a")],
              junctions: [junction("j", group_id: "g")],
              groups: [group("g")]),
    ).children.to_h { |node| [node.id, node] }
  end

  def same_group_junction_nodes
    layout.call(
      diagram(services: [service("svc", group_id: "g")],
              junctions: [junction("j1", group_id: "g"),
                          junction("j2", group_id: "g")],
              groups: [group("g")]),
    ).children.to_h { |node| [node.id, node] }
  end

  def separate_group_junction_nodes
    layout.call(
      diagram(junctions: [junction("j3", group_id: "g3"),
                          junction("j4", group_id: "g4")],
              groups: [group("g3"), group("g4")]),
    ).children.to_h { |node| [node.id, node] }
  end

  def nested_group_nodes
    nested = diagram(
      junctions: [junction("j", group_id: "inner")],
      groups: [group("outer"), group("inner", parent_id: "outer")],
    )
    layout.call(nested).children.to_h { |node| [node.id, node] }
  end

  def service_face_route
    scene = layout.call(
      diagram(services: [service("a"), service("b")],
              edges: [edge("a", "b", from: "RT")]),
    )
    [scene.edges.first.sections.first,
     scene.children.to_h { |node| [node.id, node] }]
  end

  def junction_face_route
    scene = layout.call(
      diagram(services: [service("a")], junctions: [junction("j")],
              edges: [edge("j", "a", from: "R", to: "L")]),
    )
    [scene.edges.first.sections.first,
     scene.children.to_h { |node| [node.id, node] }]
  end

  def missing_group_diagram
    diagram(junctions: [junction("j", group_id: "missing")])
  end

  def cyclic_group_diagram
    diagram(
      services: [service("a", group_id: "one")],
      groups: [group("one", parent_id: "two"),
               group("two", parent_id: "one")],
    )
  end

  def obstacle_fallback_scene
    transform = described_class.new
    allow(transform).to receive(:obstacles_for).and_raise("boom")
    transform.call(
      diagram(services: [service("a"), service("b")],
              edges: [edge("a", "b")]),
    )
  end

  def router_failure_scene
    transform = described_class.new
    allow(transform).to receive(:architecture_edge_router)
      .and_return(failing_router)
    transform.call(router_failure_diagram)
  end

  def failing_router
    calls = 0
    instance_double(Sirena::Renderer::ArchitectureEdgeRouter).tap do |router|
      allow(router).to receive(:route) do |from:, to:, **|
        calls += 1
        raise "boom" if calls == 1

        alternate_route(from, to)
      end
    end
  end

  def alternate_route(from, to)
    [from[:point], { x: from[:point][:x], y: from[:point][:y] + 10 },
     to[:point]]
  end

  def router_failure_diagram
    diagram(services: [service("a"), service("b"), service("c")],
            edges: [edge("a", "b"), edge("b", "c")])
  end

  def unrelated_group_route
    scene = layout.call(
      diagram(
        services: [service("a", group_id: "ga"),
                   service("middle", group_id: "gm"),
                   service("b", group_id: "gb")],
        groups: [group("ga"), group("gm"), group("gb")],
        edges: [edge("a", "b", from: "B", to: "T")],
      ),
    )
    [scene, scene.children.find { |node| node.id == "gm" }]
  end

  def ir_equivalence_diagram
    outer = group("outer")
    inner = group("inner", parent_id: outer.id)
    api = service("api", group_id: inner.id)
    worker = service("worker", group_id: outer.id)
    router = junction("route", group_id: inner.id)
    diagram(
      services: [api, worker], junctions: [router], groups: [outer, inner],
      edges: [edge("api", "route", from: "B", to: "T", label: "queue"),
              edge("route", "worker", from: "R", to: "L")]
    )
  end

  def inputs_unchanged_after_layout?
    private_diagram = ir_equivalence_diagram
    graph = Sirena::Notation::Mermaid::IRAdapters::Architecture
      .call(private_diagram)
    before = [Marshal.dump(private_diagram), Marshal.dump(graph)]
    layout.call(private_diagram)
    layout.call(graph)
    [Marshal.dump(private_diagram), Marshal.dump(graph)] == before
  end

  def groups_with_services(count)
    groups = Array.new(count) { |index| group("g#{index}") }
    services = groups.map do |item|
      service("service_#{item.id}", group_id: item.id)
    end
    [groups, services]
  end

  def group_ids(scene)
    scene.children.filter_map do |node|
      node.id if node.kind == "group"
    end
  end

  it "returns a typed final Scene" do
    expect(routed_scene).to be_a(described_class::Scene)
  end

  it "lays out nested direct graph IR byte-identically to its private model" do
    private_diagram = ir_equivalence_diagram
    graph = Sirena::Notation::Mermaid::IRAdapters::Architecture
      .call(private_diagram)

    expect(Marshal.dump(layout.call(graph)))
      .to eq(Marshal.dump(layout.call(private_diagram)))
  end

  it "does not mutate either private or graph input during layout" do
    expect(inputs_unchanged_after_layout?).to be(true)
  end

  it "returns typed final nodes" do
    expect(routed_scene.children).to all(be_a(described_class::Node))
  end

  it "stores routed edge endpoints" do
    expect(routed_scene.edges.first)
      .to have_attributes(source: "a", target: "b")
  end

  it "stores routed edge labels" do
    expect(routed_scene.edges.first.labels.first.text).to eq("HTTP")
  end

  it "positions junctions outside service boxes" do
    nodes = junction_scene.children.to_h { |node| [node.id, node] }
    expect(overlap?(nodes["a"], nodes["mid"])).to be(false)
  end

  it "stores final junction dimensions" do
    mid = junction_scene.children.find { |node| node.id == "mid" }
    expect(mid).to have_attributes(
      width: described_class::DEFAULT_JUNCTION_SIZE.to_f,
      height: described_class::DEFAULT_JUNCTION_SIZE.to_f,
    )
  end

  it "sizes the canvas around positioned junctions" do
    scene = junction_scene
    mid = scene.children.find { |node| node.id == "mid" }
    expect(scene.width).to be >= mid.x + mid.width
  end

  it "keeps both typed edges that route through a junction" do
    expect(junction_route_scene.edges.map { |item| [item.source, item.target] })
      .to eq([%w[left mid], %w[mid right]])
  end

  it "stores junction routes as typed sections" do
    expect(junction_route_scene.edges.flat_map(&:sections))
      .to all(be_a(described_class::Section))
  end

  it "sizes a junction-only canvas from the junction plus spacing" do
    scene = layout.call(diagram(junctions: [junction("mid")]))
    mid = scene.children.fetch(0)
    spacing = described_class::DEFAULT_SPACING

    expect([scene.width, scene.height])
      .to eq([mid.x + mid.width + spacing, mid.y + mid.height + spacing])
  end

  it "keeps a junction-only group separate from other services" do
    expect(overlap?(mixed_group_nodes["a"], mixed_group_nodes["j"]))
      .to be(false)
  end

  it "positions a junction-only group below other services" do
    nodes = mixed_group_nodes
    spacing = described_class::DEFAULT_SPACING
    expected_y = nodes["a"].y + nodes["a"].height + spacing
    expect(nodes["j"].y).to eq(expected_y)
  end

  it "advances junction rows horizontally" do
    same_group = same_group_junction_nodes
    spacing = described_class::DEFAULT_SPACING
    expect(same_group["j2"].x - same_group["j1"].x)
      .to eq(described_class::DEFAULT_JUNCTION_SIZE + spacing)
  end

  it "keeps junctions in one row vertically aligned" do
    same_group = same_group_junction_nodes
    expect(same_group["j2"].y).to eq(same_group["j1"].y)
  end

  it "advances junction-only groups vertically" do
    separate_groups = separate_group_junction_nodes
    spacing = described_class::DEFAULT_SPACING
    expect(separate_groups["j4"].y - separate_groups["j3"].y)
      .to eq(described_class::DEFAULT_JUNCTION_SIZE + spacing)
  end

  it "bounds junction-only and nested groups" do
    nodes = nested_group_nodes
    summary = [nodes.keys.sort, overlap?(nodes["inner"], nodes["j"]),
               contains?(nodes["inner"], nodes["j"]),
               contains?(nodes["outer"], nodes["inner"])]
    expect(summary).to eq([%w[inner j outer], true, true, true])
  end

  it "preserves declaration order for groups at the same depth" do
    groups, services = groups_with_services(8)
    scene = layout.call(diagram(services: services, groups: groups))
    expect(group_ids(scene)).to eq(groups.map(&:id))
  end

  it "omits empty group chains without non-finite dimensions" do
    scene = layout.call(
      diagram(groups: [group("a"), group("b", parent_id: "a")]),
    )
    expect([scene.children, [scene.width, scene.height].all?(&:finite?)])
      .to eq([[], true])
  end

  it "stores multi-character face routes as typed points" do
    section, = service_face_route
    expect([section.start_point, section.end_point])
      .to all(be_a(described_class::Point))
  end

  it "starts multi-character face routes on the recognized source side" do
    section, nodes = service_face_route
    expect(section.start_point.x).to eq(nodes["a"].x + nodes["a"].width)
  end

  it "ends multi-character face routes on the recognized target side" do
    section, nodes = service_face_route
    expect(section.end_point.x).to eq(nodes["b"].x)
  end

  it "uses the literal declared source face even when it points away" do
    section, nodes = junction_face_route
    expect(section.start_point.x).to eq(nodes["j"].x + nodes["j"].width)
  end

  it "uses the literal declared target face even when it points away" do
    section, nodes = junction_face_route
    expect(section.end_point.x).to eq(nodes["a"].x)
  end

  it "refuses missing groups" do
    expect { layout.call(missing_group_diagram) }
      .to raise_error(Sirena::Layout::LayoutError)
  end

  it "refuses cyclic group ancestry" do
    expect { layout.call(cyclic_group_diagram) }
      .to raise_error(Sirena::Layout::LayoutError)
  end

  it "isolates a router failure to its edge and preserves later routing" do
    scene = router_failure_scene
    bend_points = scene.edges.map { |item| item.sections.first.bend_points }
    expect([scene.edges.length, bend_points.map(&:length)]).to eq([2, [0, 1]])
  end

  it "does not raise when obstacle discovery fails" do
    expect { obstacle_fallback_scene }.not_to raise_error
  end

  it "falls back to a straight section when obstacle discovery fails" do
    expect(obstacle_fallback_scene.edges.first.sections.first.bend_points)
      .to be_empty
  end

  it "routes around an unrelated group boundary" do
    scene, middle = unrelated_group_route
    crossings = points(scene.edges.first).each_cons(2).map do |first, last|
      segment_crosses?(middle, first, last)
    end
    expect(crossings).to all(be(false))
  end
end
