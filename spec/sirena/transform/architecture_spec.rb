# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Transform::ArchitectureTransform do
  let(:transform) { described_class.new }

  describe "#to_graph" do
    context "with a junction routing an edge between two services" do
      # Mirrors spec/mermaid/architecture/011: services connect through a
      # junction rather than to each other directly.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "left", label: "Left", icon: "server"),
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "right", label: "Right", icon: "server"),
          ],
          junctions: [
            Sirena::Diagram::ArchitectureDiagram::Junction.new(id: "mid", group_id: nil),
          ],
          groups: [],
          edges: [
            Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "left", to_id: "mid", from_position: "R", to_position: "L"),
            Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "mid", to_id: "right", from_position: "R", to_position: "L"),
          ]
        )
      end

      it "positions the junction alongside the services" do
        graph = transform.to_graph(diagram)

        expect(graph[:junctions]).to have_key("mid")
        mid = graph[:junctions]["mid"]
        expect(mid[:width]).to eq(described_class::DEFAULT_JUNCTION_SIZE)
        expect(mid[:height]).to eq(described_class::DEFAULT_JUNCTION_SIZE)
      end

      it "resolves edges that connect to the junction, not only services" do
        graph = transform.to_graph(diagram)

        # Both edges route through "mid" - if position_edges only looked up
        # service_positions, neither would resolve and both would be dropped.
        expect(graph[:edges].length).to eq(2)
        expect(graph[:edges].map { |e| [e[:edge].from_id, e[:edge].to_id] })
          .to eq([%w[left mid], %w[mid right]])
      end
    end

    context "with only a junction and no services or groups" do
      let(:junction_only_diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [],
          junctions: [Sirena::Diagram::ArchitectureDiagram::Junction.new(id: "mid", group_id: nil)],
          groups: [],
          edges: []
        )
      end

      it "sizes the canvas from the junction, not only services and groups" do
        graph = transform.to_graph(junction_only_diagram)
        mid = graph[:junctions]["mid"]

        # With no service or group extents, an unaccounted-for junction
        # would leave width/height at the bare DEFAULT_SPACING floor.
        expect(graph[:width]).to eq(mid[:x] + mid[:width] + described_class::DEFAULT_SPACING)
        expect(graph[:height]).to eq(mid[:y] + mid[:height] + described_class::DEFAULT_SPACING)
      end
    end

    context "with a junction in the same group as a service" do
      # Mirrors the constructed input from the round-5 Codex review:
      # service a(server)[A] / junction j / a:R -- L:j
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "a", label: "A", icon: "server"),
          ],
          junctions: [
            Sirena::Diagram::ArchitectureDiagram::Junction.new(id: "j", group_id: nil),
          ],
          groups: [],
          edges: [
            Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "a", to_id: "j", from_position: "R", to_position: "L"),
          ]
        )
      end

      def rectangles_overlap?(a, b)
        a[:x] < b[:x] + b[:width] && b[:x] < a[:x] + a[:width] &&
          a[:y] < b[:y] + b[:height] && b[:y] < a[:y] + a[:height]
      end

      it "does not place the junction on top of the service" do
        graph = transform.to_graph(diagram)
        service = graph[:services]["a"]
        junction = graph[:junctions]["j"]

        expect(rectangles_overlap?(service, junction)).to be(false)
      end
    end

    context "with a junction in a group that has no services of its own" do
      # Mirrors the round-2 Codex review: group g(cloud)[G] / service a(server)[A]
      # (outside g) / junction j in g. The junction's own group has no
      # services to anchor its row against, so it falls back to a shared
      # cursor - which must clear every service in the WHOLE diagram, not
      # just start at DEFAULT_SPACING regardless of what other groups
      # already placed there.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "a", label: "A", icon: "server"),
          ],
          junctions: [
            Sirena::Diagram::ArchitectureDiagram::Junction.new(id: "j", group_id: "g"),
          ],
          groups: [
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "g", label: "G", icon: "cloud"),
          ],
          edges: []
        )
      end

      def rectangles_overlap?(a, b)
        a[:x] < b[:x] + b[:width] && b[:x] < a[:x] + a[:width] &&
          a[:y] < b[:y] + b[:height] && b[:y] < a[:y] + a[:height]
      end

      it "does not place the junction on a service positioned under a different group" do
        graph = transform.to_graph(diagram)
        service = graph[:services]["a"]
        junction = graph[:junctions]["j"]

        expect(rectangles_overlap?(service, junction)).to be(false)
      end
    end

    context "with a junction naming a group nobody declared" do
      # service s1(server)[S1] / junction j1 in nosuchgroup / s1:R --> L:j1.
      # `in <group>` names a group_id, not a reference to a declared
      # Group — nothing upstream checks it resolves. position_junctions
      # only walks [:root] + diagram.groups.map(&:id), so a group_id
      # matching no declared group used to make the junction (and its
      # edge) vanish from the graph with no error at all. Refused up
      # front by ArchitectureDiagram#valid? instead.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "s1", label: "S1", icon: "server"),
          ],
          junctions: [
            Sirena::Diagram::ArchitectureDiagram::Junction.new(id: "j1", group_id: "nosuchgroup"),
          ],
          groups: [],
          edges: [
            Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "s1", to_id: "j1", from_position: "R", to_position: "L"),
          ]
        )
      end

      it "raises instead of silently dropping the junction and its edge" do
        expect { transform.to_graph(diagram) }
          .to raise_error(Sirena::Transform::TransformError)
      end
    end

    context "with a junction positioned on the wrong side of a directional edge" do
      # service a(server)[A] / junction j / j:R -- L:a. The junction's
      # default placement lands to the RIGHT of a, but the edge hint asks
      # for j's right face to meet a's left face.
      #
      # The transform does NOT mirror which face a line attaches to -
      # ArchitectureEdgeRouter draws around the obstacle instead (see
      # architecture_edge_router_spec.rb's obstacle-routing contexts), so
      # this spec only needs to check the transform hands back the literal
      # declared side, unmirrored.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "a", label: "A", icon: "server"),
          ],
          junctions: [
            Sirena::Diagram::ArchitectureDiagram::Junction.new(id: "j", group_id: nil),
          ],
          groups: [],
          edges: [
            Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "j", to_id: "a", from_position: "R", to_position: "L"),
          ]
        )
      end

      it "resolves to the literal declared side, never a mirrored one" do
        graph = transform.to_graph(diagram)
        edge = graph[:edges].first

        expect(edge[:from_side]).to eq("R")
        expect(edge[:to_side]).to eq("L")
      end
    end

    context "with a grammar-valid but multi-character position token" do
      # a:RT -- L:b. The grammar's match("[LRTB]").repeat(1) has no upper
      # bound, so "RT" parses cleanly - grammar-valid input, not something
      # this diagram type refuses. ArchitectureEdgeRouter::FACE_NORMAL only
      # has single-character keys ("L"/"R"/"T"/"B"), so passing "RT" through
      # raises the moment the router's search actually runs (the straight
      # line short-circuit hides it when nothing forces a detour). The old
      # pre-router code never raised here - calculate_connection_point's
      # case/when/else silently defaulted an unrecognized value - so this
      # is a regression the router's stricter FACE_NORMAL lookup
      # introduced, fixed at the boundary where the raw token first meets
      # a real diagram: never hand the router something it cannot look up.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "a", label: "A", icon: "server"),
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "b", label: "B", icon: "server"),
          ],
          groups: [],
          edges: [
            Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "a", to_id: "b", from_position: "RT",
                                                           to_position: "L"),
          ]
        )
      end

      it "falls back to a recognized face rather than passing the raw token through" do
        graph = transform.to_graph(diagram)
        edge = graph[:edges].first

        expect(%w[L R T B].include?(edge[:from_side])).to be(true)
        expect(%w[L R T B].include?(edge[:to_side])).to be(true)
      end
    end

    context "with a group whose only member is a junction" do
      # Mirrors the round-5 Codex review: group g(cloud)[G] / junction j in g
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [],
          junctions: [
            Sirena::Diagram::ArchitectureDiagram::Junction.new(id: "j", group_id: "g"),
          ],
          groups: [
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "g", label: "G", icon: "cloud"),
          ],
          edges: []
        )
      end

      it "draws a boundary around the group instead of dropping it" do
        graph = transform.to_graph(diagram)

        expect(graph[:groups]).to have_key("g")
      end

      it "sizes the boundary to actually contain the junction" do
        graph = transform.to_graph(diagram)
        bounds = graph[:groups]["g"]
        junction = graph[:junctions]["j"]

        expect(bounds[:x]).to be <= junction[:x]
        expect(bounds[:y]).to be <= junction[:y]
        expect(bounds[:x] + bounds[:width]).to be >= junction[:x] + junction[:width]
        expect(bounds[:y] + bounds[:height]).to be >= junction[:y] + junction[:height]
      end
    end

    context "with a parent group declared before its childless-of-its-own child" do
      # A parent group with no direct service/junction reads its child's
      # bounds in calculate_group_bounds. diagram.groups is source order,
      # and mermaid's natural nesting syntax declares the parent group
      # first (`group outer` then `group inner in outer`) - if bounds are
      # built in that same order, the parent reads bounds["inner"] before
      # "inner" has been processed, gets nil, and its min/max stay at their
      # Float::INFINITY/-INFINITY seed forever, which later NaNs out in
      # calculate_total_width/height's Infinity + -Infinity arithmetic.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "s", label: "S", icon: "server", group_id: "inner"),
          ],
          junctions: [],
          groups: [
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "outer", label: "Outer", icon: "cloud"),
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "inner", label: "Inner", icon: "cloud", parent_id: "outer"),
          ],
          edges: []
        )
      end

      it "does not crash rendering the width and height" do
        graph = transform.to_graph(diagram)

        expect(graph[:width]).to be_a(Numeric).and be_finite
        expect(graph[:height]).to be_a(Numeric).and be_finite
      end

      it "gives the outer group a bounding box that contains the inner group" do
        graph = transform.to_graph(diagram)
        outer = graph[:groups]["outer"]
        inner = graph[:groups]["inner"]

        expect(outer[:x]).to be <= inner[:x]
        expect(outer[:y]).to be <= inner[:y]
        expect(outer[:x] + outer[:width]).to be >= inner[:x] + inner[:width]
        expect(outer[:y] + outer[:height]).to be >= inner[:y] + inner[:height]
      end
    end

    context "with a chain of nested groups that have no services or junctions anywhere" do
      # The single-level fix above lets a parent read an already-bounded
      # child. A THREE-deep chain where every group is empty exercises a
      # different path: the middle group has no members of its own but a
      # non-empty child_groups list, so it does not hit the direct-leaf
      # skip either - it falls into the "use child group bounds" branch,
      # finds its own child has no bounds entry, and (before this fix)
      # wrote an Infinity/-Infinity entry of its own, which then NaN'd out
      # the outermost group's max_x/max_y comparison one level further up.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [],
          junctions: [],
          groups: [
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "outer", label: "Outer", icon: "cloud"),
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "mid", label: "Mid", icon: "cloud", parent_id: "outer"),
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "inner", label: "Inner", icon: "cloud", parent_id: "mid"),
          ],
          edges: []
        )
      end

      it "does not crash rendering the width and height" do
        graph = transform.to_graph(diagram)

        expect(graph[:width]).to be_a(Numeric).and be_finite
        expect(graph[:height]).to be_a(Numeric).and be_finite
      end

      it "draws no bounding box for any of the three empty groups" do
        graph = transform.to_graph(diagram)

        expect(graph[:groups]).to be_empty
      end
    end

    context "with a cyclic group parent chain" do
      # group a in b / group b in a - grammar-valid (nothing upstream
      # validates that Group#parent_id chains terminate). A group being
      # its own ancestor is malformed regardless of whether each cyclic
      # group happens to carry its own service, so
      # ArchitectureDiagram#valid? refuses the whole shape up front
      # (Containment.looping_pair, the same check Flowchart#parent_cycle?
      # uses) rather than letting group_depth's recursion-cutoff produce a
      # bounding box for it. That cutoff still exists to keep group_depth
      # itself from looping forever on a diagram built by hand that
      # bypasses #valid? — see spec/sirena/renderer/architecture_spec.rb,
      # "with a cyclic group parent chain", which proves the renderer's
      # own equivalent guard the same way, on a hand-built layout that
      # never goes through #valid?.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "s1", label: "S1", icon: "server", group_id: "a"),
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "s2", label: "S2", icon: "server", group_id: "b"),
          ],
          junctions: [],
          groups: [
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "a", label: "A", icon: "cloud", parent_id: "b"),
            Sirena::Diagram::ArchitectureDiagram::Group.new(id: "b", label: "B", icon: "cloud", parent_id: "a"),
          ],
          edges: []
        )
      end

      it "refuses the diagram instead of rendering a nonsensical hierarchy" do
        expect { Timeout.timeout(2) { transform.to_graph(diagram) } }
          .to raise_error(Sirena::Transform::TransformError)
      end
    end
  end

  describe "#position_junctions (direct)" do
    # These call the private method directly with hand-built inputs so the
    # cursor arithmetic can be pinned exactly, independent of what
    # position_services would ever actually produce.
    let(:transform) { described_class.new }
    let(:root_group) { :root }

    def group_double(id)
      Sirena::Diagram::ArchitectureDiagram::Group.new(id: id, label: id, icon: "cloud")
    end

    def junction_double(id)
      Sirena::Diagram::ArchitectureDiagram::Junction.new(id: id, group_id: nil)
    end

    context "when a group has zero junctions but does have services" do
      # Mirrors the `next if junctions.empty?` guard at position_junctions.
      # Without it, a junction-less group would still fall into the
      # group_services.any? branch and shift the cursor for every group
      # that follows, using a row computed for junctions that don't exist.
      let(:diagram) { Sirena::Diagram::ArchitectureDiagram.new(services: [], groups: [group_double("g1")], junctions: [], edges: []) }
      let(:hierarchy) { { junctions_by_group: { root: [], "g1" => [junction_double("j1")] } } }
      let(:service_positions) do
        { "svcA" => { x: 0, y: 0, width: 20, height: 0, group_id: root_group } }
      end

      it "leaves the cursor untouched by the empty group" do
        positions = transform.send(:position_junctions, diagram, hierarchy, service_positions)

        # junction_fallback_floor(service_positions) = 0 + 0 + DEFAULT_SPACING = 40.
        # If the empty root group were not skipped, its phantom row (built
        # from svcA) would push this to 86 before g1 is ever reached.
        expect(positions["j1"][:y]).to eq(40)
      end
    end

    context "with a group with services, then two junction-only groups after it" do
      # Exercises: per-junction row_x advancement within one group, the
      # group_services.any? cursor update (row-relative), and the
      # group_services.empty? cursor update (shared-floor fallback),
      # chained so each group's effect is visible in the next group's
      # position rather than only in its own.
      let(:diagram) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [],
          groups: [group_double("g1"), group_double("g2"), group_double("g3")],
          junctions: [],
          edges: []
        )
      end
      let(:hierarchy) do
        {
          junctions_by_group: {
            root: [],
            "g1" => [junction_double("j1"), junction_double("j1b")],
            "g2" => [junction_double("j2")],
            "g3" => [junction_double("j3")],
          },
        }
      end
      let(:service_positions) do
        # height: 0 (unlike any real service, which is always
        # DEFAULT_SERVICE_HEIGHT) so the group's own row sits below the
        # global junction_fallback_floor, making the row-relative branch
        # (group_services.any?) actually raise the cursor instead of being
        # dominated by the floor every time.
        { "svcA" => { x: 0, y: 0, width: 20, height: 0, group_id: "g1" } }
      end

      it "advances row_x across junctions in the same group" do
        positions = transform.send(:position_junctions, diagram, hierarchy, service_positions)

        expect(positions["j1"][:x]).to eq(60)
        expect(positions["j1b"][:x]).to eq(112)
      end

      it "raises the cursor from the row a group's own services sit on" do
        positions = transform.send(:position_junctions, diagram, hierarchy, service_positions)

        # row_top (0) + (DEFAULT_SERVICE_HEIGHT - DEFAULT_JUNCTION_SIZE) / 2.0 (34) = 34
        expect(positions["j1"][:y]).to eq(34)
        # group_services.any? branch: current_y = max(40, 34 + 12 + 40) = 86.
        # g2 has no services of its own, so it falls back to this cursor.
        expect(positions["j2"][:y]).to eq(86)
      end

      it "advances the shared cursor again after a junction-only group" do
        positions = transform.send(:position_junctions, diagram, hierarchy, service_positions)

        # g2 (junction-only) pushes current_y to 86 + 12 + 40 = 138 for g3.
        expect(positions["j3"][:y]).to eq(138)
        expect(positions["j3"][:y]).not_to eq(positions["j2"][:y])
      end
    end
  end
end
