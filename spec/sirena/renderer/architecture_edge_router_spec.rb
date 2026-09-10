# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/architecture_edge_router"

RSpec.describe Sirena::Renderer::ArchitectureEdgeRouter do
  let(:router) { described_class.new }

  def box(x:, y:, width: 120, height: 80)
    { x: x, y: y, width: width, height: height }
  end

  # Mirrors ArchitectureTransform#calculate_connection_point, so specs can
  # build a genuine anchor for a declared side rather than an arbitrary
  # point that happens not to sit on the box's face.
  def face_point(box, side)
    case side
    when "L" then { x: box[:x], y: box[:y] + (box[:height] / 2) }
    when "R" then { x: box[:x] + box[:width], y: box[:y] + (box[:height] / 2) }
    when "T" then { x: box[:x] + (box[:width] / 2), y: box[:y] }
    when "B" then { x: box[:x] + (box[:width] / 2), y: box[:y] + box[:height] }
    end
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
    centre = { x: box[:x] + (box[:width] / 2.0), y: box[:y] + (box[:height] / 2.0) }
    { x: anchor[:x] <=> centre[:x], y: anchor[:y] <=> centre[:y] }
  end

  # Arriving at a face means moving the opposite way from leaving it.
  def entry_direction(box, side)
    exit = exit_direction(box, side)
    { x: -exit[:x], y: -exit[:y] }
  end

  # General segment-vs-box interior test, independent of the router's own
  # implementation - a border touch does not count as a crossing.
  def segment_crosses?(box, p1, p2)
    (0..200).any? do |i|
      t = i / 200.0
      x = p1[:x] + ((p2[:x] - p1[:x]) * t)
      y = p1[:y] + ((p2[:y] - p1[:y]) * t)
      x > box[:x] && x < box[:x] + box[:width] &&
        y > box[:y] && y < box[:y] + box[:height]
    end
  end

  def path_clear_of?(points, box)
    points.each_cons(2).none? { |p1, p2| segment_crosses?(box, p1, p2) }
  end

  describe "#route" do
    context "when nothing is in the way" do
      it "returns the straight line, with no extra bends" do
        a = box(x: 40, y: 40)
        b = box(x: 200, y: 40)

        points = router.route(from: endpoint(a, "R"), to: endpoint(b, "L"), obstacles: [])

        expect(points).to eq([face_point(a, "R"), face_point(b, "L")])
      end
    end

    context "with a third-party obstacle in the way" do
      # A, B, C in a row. A->C would run straight through B if B weren't
      # excluded from "own endpoints" and included as an ordinary obstacle.
      def row
        [box(x: 40, y: 40), box(x: 200, y: 40), box(x: 360, y: 40)]
      end

      it "never crosses the interior of the obstacle" do
        a, b, c = row
        points = router.route(from: endpoint(a, "R"), to: endpoint(c, "L"), obstacles: [b])

        expect(path_clear_of?(points, b)).to be(true)
      end

      it "still starts and ends at the exact anchors" do
        a, b, c = row
        points = router.route(from: endpoint(a, "R"), to: endpoint(c, "L"), obstacles: [b])

        expect(points.first).to eq(face_point(a, "R"))
        expect(points.last).to eq(face_point(c, "L"))
      end
    end

    context "with case 011's on_prem obstacle set" do
      # Real geometry from spec/mermaid/architecture/011: 8 services + 6
      # junctions, transformed with adjust_positions_for_edges removed.
      # edge:R -- L:firewall crosses server1 on a straight line - this is
      # the case-011 reproducer, pinned as a property (no interior
      # crossing) rather than a copied coordinate list. It also happens to
      # be dense enough that the raw grid search returns several
      # consecutive collinear points (up to 7 in a row along one wall),
      # which makes it the natural case for pinning collapse_collinear too.
      def case_011_edge_route
        diagram = Sirena::Parser::Architecture.new.parse(
          File.read(File.expand_path(
                      "../../mermaid/architecture/011_rendering_architecture_spec_architecture_10.mmd", __dir__
                    ))
        )
        graph = Sirena::Transform::ArchitectureTransform.new.to_graph(diagram)
        nodes = graph[:services].merge(graph[:junctions])
        edge_entry = graph[:edges].find { |e| e[:edge].from_id == "edge" && e[:edge].to_id == "firewall" }
        from = { point: { x: edge_entry[:from_x], y: edge_entry[:from_y] }, box: nodes["edge"], side: "R" }
        to = { point: { x: edge_entry[:to_x], y: edge_entry[:to_y] }, box: nodes["firewall"], side: "L" }
        obstacles = nodes.except("edge", "firewall").values

        [router.route(from: from, to: to, obstacles: obstacles), obstacles]
      end

      it "routes the cross-group edge around every peer service" do
        points, obstacles = case_011_edge_route

        obstacles.each do |obstacle|
          expect(path_clear_of?(points, obstacle)).to be(true)
        end
      end

      it "collapses runs of collinear points into a single bend" do
        points, = case_011_edge_route

        points.each_cons(3) do |before, at, after|
          same_direction = (at[:x] <=> before[:x]) == (after[:x] <=> at[:x]) &&
            (at[:y] <=> before[:y]) == (after[:y] <=> at[:y])
          expect(same_direction).to be(false), "#{at} is collinear with its neighbours and should have been dropped"
        end
      end
    end

    context "with the B--T diagonal case (no third-party obstacle at all)" do
      # service a(server)[A] / service b(server)[B]. a:R -- T:b. The
      # straight line from a's R face to b's T face clips through b's own
      # interior - proves from/to boxes are clearance obstacles, not just
      # "every other box" (there is no third box here at all).
      def pair
        [box(x: 40, y: 40), box(x: 200, y: 40)]
      end

      it "never crosses its own target's interior" do
        a, b = pair
        points = router.route(from: endpoint(a, "R"), to: endpoint(b, "T"), obstacles: [])

        expect(path_clear_of?(points, b)).to be(true)
      end

      it "still starts and ends at the exact anchors" do
        a, b = pair
        points = router.route(from: endpoint(a, "R"), to: endpoint(b, "T"), obstacles: [])

        expect(points.first).to eq(face_point(a, "R"))
        expect(points.last).to eq(face_point(b, "T"))
      end
    end

    context "with every declared exit and entry face" do
      # Parameterized over every (from_side, to_side) pair: the first move
      # leaves in the outward normal of from_side, the last move arrives in
      # the inward normal of to_side (the opposite of to_side's outward
      # normal) - whenever the path has more than 2 points (a straight
      # line's direction is fixed by geometry, not by this constraint, and
      # is covered separately by the "nothing in the way" context).
      #
      # Expectations come from exit_direction/entry_direction, which derive
      # the answer from face_point's geometry against the box's own centre
      # - never from FACE_NORMAL, the constant search_grid itself reads.
      # Deriving the expectation from that same constant would only prove
      # the router agrees with itself: a sabotaged FACE_NORMAL entry would
      # produce a matching, equally wrong expectation and this spec would
      # not notice. Confirmed by flipping FACE_NORMAL["R"] by hand before
      # this fix - this spec stayed green at 16/16 while the two
      # independent crossing-checker specs above correctly went red.
      %w[L R T B].each do |from_side|
        %w[L R T B].each do |to_side|
          it "leaves via #{from_side} and arrives via #{to_side} when bent" do
            a = box(x: 40, y: 40, width: 60, height: 60)
            b = box(x: 300, y: 300, width: 60, height: 60)
            obstacle = box(x: 150, y: 150, width: 100, height: 100)

            points = router.route(from: endpoint(a, from_side), to: endpoint(b, to_side), obstacles: [obstacle])

            next if points.length == 2 # straight line: geometry decides direction, not this test

            actual_first = { x: points[1][:x] <=> points[0][:x], y: points[1][:y] <=> points[0][:y] }
            expect(actual_first).to eq(exit_direction(a, from_side))

            actual_last = { x: points[-1][:x] <=> points[-2][:x], y: points[-1][:y] <=> points[-2][:y] }
            expect(actual_last).to eq(entry_direction(b, to_side))
          end
        end
      end
    end

    context "when no route exists at all" do
      it "falls back to the straight line rather than raising" do
        a = box(x: 60, y: 60, width: 80, height: 80)
        b = box(x: 460, y: 460, width: 80, height: 80)
        from = { point: { x: 100, y: 100 }, box: a, side: "R" }
        to = { point: { x: 500, y: 500 }, box: b, side: "L" }
        # A ring of obstacles fully surrounding to's point, leaving no free
        # grid cell for the search to escape through.
        ring = [
          box(x: 400, y: 400, width: 20, height: 200),
          box(x: 600, y: 400, width: 20, height: 200),
          box(x: 400, y: 400, width: 220, height: 20),
          box(x: 400, y: 600, width: 220, height: 20),
        ]

        expect do
          points = router.route(from: from, to: to, obstacles: ring)
          expect(points).to eq([from[:point], to[:point]])
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

    it "pops entries in ascending cost order, matching a stable sort" do
      costs = [37, 2, 15, 4, 26, 4, 100, 0, 8]
      heap = heap_class.new
      costs.each_with_index { |cost, index| heap.push(cost, index) }

      popped = []
      popped << heap.pop.first until heap.empty?

      expect(popped).to eq(costs.sort)
    end

    it "keeps popping the minimum after interleaved pushes" do
      heap = heap_class.new
      heap.push(10, :a)
      heap.push(3, :b)
      expect(heap.pop).to eq([3, :b])

      heap.push(1, :c)
      heap.push(7, :d)
      expect(heap.pop).to eq([1, :c])
      expect(heap.pop).to eq([7, :d])
      expect(heap.pop).to eq([10, :a])
      expect(heap).to be_empty
    end
  end
end
