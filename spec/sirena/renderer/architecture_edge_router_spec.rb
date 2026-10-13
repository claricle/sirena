# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/architecture_edge_router"

# Pure geometry helpers, single-user (this file only): module_function so
# they can be called at describe-body level to generate examples.
module ArchitectureEdgeRouterSpecHelpers
  module_function

  def box(left:, top:, width: 120, height: 80)
    { x: left, y: top, width: width, height: height }
  end

  # Mirrors Architecture#calculate_connection_point, so specs can
  # build a genuine anchor for a declared side rather than an arbitrary
  # point that happens not to sit on the box's face.
  def face_point(box, side)
    case side
    when "L", "R" then horizontal_face_point(box, side)
    when "T", "B" then vertical_face_point(box, side)
    end
  end

  def horizontal_face_point(box, side)
    horizontal = side == "L" ? box[:x] : box[:x] + box[:width]
    { x: horizontal, y: box[:y] + (box[:height] / 2) }
  end

  def vertical_face_point(box, side)
    vertical = side == "T" ? box[:y] : box[:y] + box[:height]
    { x: box[:x] + (box[:width] / 2), y: vertical }
  end

  def endpoint(box, side)
    { point: face_point(box, side), box: box, side: side }
  end

  # The sign of (anchor - box centre), computed purely from face_point and
  # the box's own coordinates - never from FACE_NORMAL, the constant the
  # router itself uses to constrain search_grid's first/last hop. Using
  # FACE_NORMAL to build the expectation would make the spec provable only
  # against ITSELF: a wrong FACE_NORMAL entry would still match a wrong
  # expectation derived from that same wrong entry. This is independent -
  # it would give the right answer for "R" even if FACE_NORMAL["R"] were
  # sabotaged, because it never reads that constant at all.
  def exit_direction(box, side)
    anchor = face_point(box, side)
    centre = box_centre(box)
    { x: anchor[:x] <=> centre[:x], y: anchor[:y] <=> centre[:y] }
  end

  def box_centre(box)
    { x: box[:x] + (box[:width] / 2.0),
      y: box[:y] + (box[:height] / 2.0) }
  end

  # Arriving at a face means moving the opposite way from leaving it.
  def entry_direction(box, side)
    exit = exit_direction(box, side)
    { x: -exit[:x], y: -exit[:y] }
  end

  # General segment-vs-box interior test, independent of the router's own
  # implementation - a border touch does not count as a crossing.
  def segment_crosses?(box, start_point, end_point)
    (0..200).any? do |step|
      point = interpolate_segment(start_point, end_point, step / 200.0)
      point_inside?(box, point)
    end
  end

  def interpolate_segment(start_point, end_point, progress)
    { x: start_point[:x] + ((end_point[:x] - start_point[:x]) * progress),
      y: start_point[:y] + ((end_point[:y] - start_point[:y]) * progress) }
  end

  def point_inside?(box, point)
    inside_axis?(point[:x], box[:x], box[:width]) &&
      inside_axis?(point[:y], box[:y], box[:height])
  end

  def inside_axis?(coordinate, origin, extent)
    coordinate > origin && coordinate < origin + extent
  end

  def path_clear_of?(points, box)
    points.each_cons(2).none? { |p1, p2| segment_crosses?(box, p1, p2) }
  end

  # A, B, C in a row. A->C would run straight through B if B weren't
  # excluded from "own endpoints" and included as an ordinary obstacle.
  def row
    [box(left: 40, top: 40), box(left: 200, top: 40), box(left: 360, top: 40)]
  end

  # Real geometry from spec/mermaid/architecture/architecture_spec-f1819a63:
  # 8 services + 6 junctions, transformed with adjust_positions_for_edges
  # removed.
  # edge:R -- L:firewall crosses server1 on a straight line - this is
  # the case-011 reproducer, pinned as a property (no interior
  # crossing) rather than a copied coordinate list. It also happens to
  # be dense enough that the raw grid search returns several
  # consecutive collinear points (up to 7 in a row along one wall),
  # which makes it the natural case for pinning collapse_collinear too.
  def case_011_edge_route(router)
    scene = case_011_scene
    nodes = case_011_nodes(scene)
    from, to = case_011_endpoints(scene, nodes)
    obstacles = nodes.except("edge", "firewall").values
    [router.route(from: from, to: to, obstacles: obstacles), obstacles]
  end

  def case_011_scene
    path = File.expand_path(
      "../../mermaid/architecture/architecture_spec-f1819a63.mmd", __dir__
    )
    diagram = Sirena::Parser::Architecture.new.parse(File.read(path))
    Sirena::Layout::Architecture.new.call(diagram)
  end

  def case_011_nodes(scene)
    scene.children.reject { |node| node.kind == "group" }
      .to_h { |node| [node.id, node_box(node)] }
  end

  def case_011_endpoints(scene, nodes)
    section = case_011_section(scene)
    [{ point: point_hash(section.start_point),
       box: nodes["edge"], side: "R" },
     { point: point_hash(section.end_point),
       box: nodes["firewall"], side: "L" }]
  end

  def case_011_section(scene)
    edge_entry = scene.edges.find do |edge|
      edge.source == "edge" && edge.target == "firewall"
    end
    edge_entry.sections.first
  end

  def node_box(node)
    { x: node.x, y: node.y, width: node.width, height: node.height }
  end

  def point_hash(point)
    { x: point.x, y: point.y }
  end

  # service a(server)[A] / service b(server)[B]. a:R -- T:b. The
  # straight line from a's R face to b's T face clips through b's own
  # interior - proves from/to boxes are clearance obstacles, not just
  # "every other box" (there is no third box here at all).
  def pair
    [box(left: 40, top: 40), box(left: 200, top: 40)]
  end

  def segment_direction(points)
    { x: points[1][:x] <=> points[0][:x],
      y: points[1][:y] <=> points[0][:y] }
  end

  def collinear?(before, at, after)
    segment_direction([before, at]) == segment_direction([at, after])
  end

  def collinear_message(point)
    "#{point} is collinear with its neighbours and " \
      "should have been dropped"
  end

  # A straight fallback must still clear the obstacle; a broken direction
  # constraint can otherwise degrade into a crossing without being noticed.
  def face_observation(points, obstacle)
    return path_clear_of?(points, obstacle) if points.length == 2

    [segment_direction(points.first(2)), segment_direction(points.last(2))]
  end

  def expected_face_observation(points, source_box, target_box,
                                source_side, target_side)
    return true if points.length == 2

    [exit_direction(source_box, source_side),
     entry_direction(target_box, target_side)]
  end

  def interleaved_heap_observations(heap)
    heap.push(10, :a)
    heap.push(3, :b)
    first = heap.pop
    heap.push(1, :c)
    heap.push(7, :d)
    [first, heap.pop, heap.pop, heap.pop, heap.empty?]
  end
end

RSpec.describe Sirena::Renderer::ArchitectureEdgeRouter, :aggregate_failures do
  include ArchitectureEdgeRouterSpecHelpers

  let(:router) { described_class.new }

  describe "#route" do
    context "when nothing is in the way" do
      let(:a) { box(left: 40, top: 40) }
      let(:b) { box(left: 200, top: 40) }
      let(:points) do
        router.route(from: endpoint(a, "R"), to: endpoint(b, "L"),
                     obstacles: [])
      end

      it "returns the straight line, with no extra bends" do
        expect(points).to eq([face_point(a, "R"), face_point(b, "L")])
      end
    end

    context "with a third-party obstacle in the way" do
      let(:boxes) { row }
      let(:points) do
        a, b, c = boxes
        router.route(from: endpoint(a, "R"), to: endpoint(c, "L"),
                     obstacles: [b])
      end

      it "never crosses the interior of the obstacle" do
        expect(path_clear_of?(points, boxes[1])).to be(true)
      end

      it "still starts and ends at the exact anchors" do
        expect(points.first).to eq(face_point(boxes[0], "R"))
        expect(points.last).to eq(face_point(boxes[2], "L"))
      end
    end

    context "with case 011's on_prem obstacle set" do
      let(:route_result) { case_011_edge_route(router) }
      let(:points) { route_result.first }
      let(:obstacles) { route_result.last }

      it "routes the cross-group edge around every peer service" do
        obstacles.each do |obstacle|
          expect(path_clear_of?(points, obstacle)).to be(true)
        end
      end

      it "collapses runs of collinear points into a single bend" do
        points.each_cons(3) do |before, at, after|
          expect(collinear?(before, at, after), collinear_message(at))
            .to be(false)
        end
      end
    end

    context "with the B--T diagonal case (no third-party obstacle at all)" do
      let(:boxes) { pair }
      let(:a) { boxes[0] }
      let(:b) { boxes[1] }
      let(:points) do
        router.route(from: endpoint(a, "R"), to: endpoint(b, "T"),
                     obstacles: [])
      end

      it "never crosses its own target's interior" do
        expect(path_clear_of?(points, b)).to be(true)
      end

      it "still starts and ends at the exact anchors" do
        expect(points.first).to eq(face_point(a, "R"))
        expect(points.last).to eq(face_point(b, "T"))
      end
    end

    context "with every declared exit and entry face" do
      let(:a) { box(left: 40, top: 40, width: 60, height: 60) }
      let(:b) { box(left: 300, top: 300, width: 60, height: 60) }
      let(:obstacle) { box(left: 150, top: 150, width: 100, height: 100) }
      let(:route_for_faces) do
        lambda do |from_side, to_side|
          router.route(from: endpoint(a, from_side), to: endpoint(b, to_side),
                       obstacles: [obstacle])
        end
      end

      # Parameterized over every (from_side, to_side) pair: the first move
      # leaves in the outward normal of from_side, the last arrives in the
      # inward normal of to_side, whenever the path has more than 2 points
      # (a straight line's direction is fixed by geometry, not this
      # constraint, and is covered by "nothing in the way" above).
      #
      # Expectations must come from exit_direction/entry_direction (derived
      # from face_point's geometry against the box's own centre), never from
      # FACE_NORMAL - that's the constant search_grid itself reads, so
      # deriving the expectation from it would only prove the router agrees
      # with itself and miss a sabotaged FACE_NORMAL entry.
      %w[L R T B].each do |from_side|
        %w[L R T B].each do |to_side|
          it "leaves via #{from_side} and arrives via #{to_side} when bent" do
            points = route_for_faces.call(from_side, to_side)
            expect(face_observation(points, obstacle)).to eq(
              expected_face_observation(points, a, b, from_side, to_side),
            )
          end
        end
      end
    end

    context "when no route exists at all" do
      let(:from) do
        { point: { x: 100, y: 100 },
          box: box(left: 60, top: 60, width: 80, height: 80), side: "R" }
      end
      let(:to) do
        { point: { x: 500, y: 500 },
          box: box(left: 460, top: 460, width: 80, height: 80), side: "L" }
      end
      # A ring fully surrounding to's point leaves no grid cell to escape.
      let(:ring) do
        [box(left: 400, top: 400, width: 20, height: 200),
         box(left: 600, top: 400, width: 20, height: 200),
         box(left: 400, top: 400, width: 220, height: 20),
         box(left: 400, top: 600, width: 220, height: 20)]
      end

      it "falls back to the straight line rather than raising" do
        expect do
          points = router.route(from: from, to: to, obstacles: ring)
          expect(points).to eq([from[:point], to[:point]])
        end.not_to raise_error
      end
    end

    context "when from and to share the exact same point" do
      # from[:box] and to[:box] are the SAME box/side here, so from[:point]
      # == to[:point] exactly - straight_clear? still returns false because
      # a THIRD, unrelated obstacle's interior contains that point (a
      # zero-length segment sitting strictly inside a box still counts as
      # crossing it, per segment_crosses_box?'s own c1==c2 branch). That
      # sends search_grid a start and goal at identical grid indices, which
      # its own `return nil if start == goal` guard exists to handle -
      # otherwise reconstruct would walk a state graph with no path to it.
      let(:a) { box(left: 100, top: 100) }
      let(:anchor) { { point: face_point(a, "R"), box: a, side: "R" } }
      let(:blocker) { box(left: 180, top: 100, width: 80, height: 80) }

      it "falls back to the same point twice rather than raising" do
        expect do
          points = router.route(from: anchor, to: anchor, obstacles: [blocker])
          expect(points).to eq([anchor[:point], anchor[:point]])
        end.not_to raise_error
      end
    end
  end

  describe "the private MinHeap search_grid uses" do
    # search_grid used to re-sort the whole frontier on every pop
    # (`frontier.sort_by! { ... }; frontier.shift`), which is an O(n log n)
    # re-sort where a proper priority queue is O(log n) - measured
    # superlinear wall-clock growth across obstacle counts, real on a
    # diagram with 100+ services and long edges. MinHeap replaces it; this
    # pins the one property it has to hold for Dijkstra to stay correct -
    # pop always returns the lowest-cost entry pushed so far - reached via
    # const_get since it is private_constant (an implementation detail,
    # not part of this class's public geometry API).
    let(:heap_class) { described_class.const_get(:MinHeap) }

    let(:heap) { heap_class.new }
    let(:costs) { [37, 2, 15, 4, 26, 4, 100, 0, 8] }
    let(:filled_heap) do
      costs.each_with_index { |cost, index| heap.push(cost, index) }
      heap
    end

    it "pops entries in ascending cost order" do
      popped = []
      popped << filled_heap.pop.first until filled_heap.empty?

      expect(popped).to eq(costs.sort)
    end

    it "keeps popping the minimum after interleaved pushes" do
      expect(interleaved_heap_observations(heap)).to eq(
        [[3, :b], [1, :c], [7, :d], [10, :a], true],
      )
    end
  end
end
