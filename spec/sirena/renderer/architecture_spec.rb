# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/architecture"
require "sirena/diagram/architecture"
require "timeout"

RSpec.describe Sirena::Renderer::ArchitectureRenderer do
  let(:renderer) { described_class.new }

  describe "#render" do
    let(:diagram) do
      Sirena::Diagram::ArchitectureDiagram.new(
        services: [
          Sirena::Diagram::ArchitectureDiagram::Service.new(
            id: "db",
            label: "Database",
            icon: "database",
            group_id: nil
          ),
          Sirena::Diagram::ArchitectureDiagram::Service.new(
            id: "server",
            label: "Server",
            icon: "server",
            group_id: nil
          ),
        ],
        groups: [],
        edges: [
          Sirena::Diagram::ArchitectureDiagram::Edge.new(
            from_id: "db",
            to_id: "server",
            from_position: "R",
            to_position: "L",
            label: nil
          ),
        ]
      )
    end

    let(:layout) do
      {
        services: {
          "db" => {
            service: diagram.services[0],
            x: 40,
            y: 40,
            width: 120,
            height: 80,
            group_id: :root,
          },
          "server" => {
            service: diagram.services[1],
            x: 200,
            y: 40,
            width: 120,
            height: 80,
            group_id: :root,
          },
        },
        groups: {},
        edges: [
          {
            edge: diagram.edges[0],
            from_x: 160,
            from_y: 80,
            to_x: 200,
            to_y: 80,
            from_side: "R",
            to_side: "L",
          },
        ],
        width: 400,
        height: 200,
      }
    end

    it "renders an SVG document" do
      svg = renderer.render(layout)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to eq(400)
      expect(svg.height).to eq(200)
    end

    it "renders services" do
      svg = renderer.render(layout)
      svg_string = svg.to_s

      expect(svg_string).to include('id="service-db"')
      expect(svg_string).to include('id="service-server"')
    end

    it "renders service labels" do
      svg = renderer.render(layout)
      svg_string = svg.to_s

      expect(svg_string).to include("Database")
      expect(svg_string).to include("Server")
    end

    it "renders edges" do
      svg = renderer.render(layout)
      svg_string = svg.to_s

      expect(svg_string).to include('id="edge-db-server"')
    end

    context "with groups" do
      let(:diagram_with_groups) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(
              id: "db",
              label: "Database",
              icon: "database",
              group_id: "api"
            ),
          ],
          groups: [
            Sirena::Diagram::ArchitectureDiagram::Group.new(
              id: "api",
              label: "API",
              icon: "cloud",
              parent_id: nil
            ),
          ],
          edges: []
        )
      end

      let(:layout_with_groups) do
        {
          services: {
            "db" => {
              service: diagram_with_groups.services[0],
              x: 70,
              y: 70,
              width: 120,
              height: 80,
              group_id: "api",
            },
          },
          groups: {
            "api" => {
              group: diagram_with_groups.groups[0],
              x: 40,
              y: 40,
              width: 180,
              height: 140,
            },
          },
          edges: [],
          width: 300,
          height: 250,
        }
      end

      it "renders group boundaries" do
        svg = renderer.render(layout_with_groups)
        svg_string = svg.to_s

        expect(svg_string).to include('id="group-api"')
      end

      it "renders group labels" do
        svg = renderer.render(layout_with_groups)
        svg_string = svg.to_s

        expect(svg_string).to include("API")
      end
    end

    context "with edge labels" do
      let(:layout_with_label) do
        layout_copy = layout.dup
        layout_copy[:edges] = [
          {
            edge: Sirena::Diagram::ArchitectureDiagram::Edge.new(
              from_id: "db",
              to_id: "server",
              from_position: "R",
              to_position: "L",
              label: "HTTP"
            ),
            from_x: 160,
            from_y: 80,
            to_x: 200,
            to_y: 80,
            from_side: "R",
            to_side: "L",
          },
        ]
        layout_copy
      end

      it "renders edge labels" do
        svg = renderer.render(layout_with_label)
        svg_string = svg.to_s

        expect(svg_string).to include("HTTP")
      end
    end

    context "with a junction" do
      let(:junction) { Sirena::Diagram::ArchitectureDiagram::Junction.new(id: "mid", group_id: nil) }

      let(:layout_with_junction) do
        layout_copy = layout.dup
        layout_copy[:junctions] = {
          "mid" => {
            junction: junction,
            x: 300,
            y: 40,
            width: 12,
            height: 12,
            group_id: :root,
          },
        }
        layout_copy
      end

      it "renders a circle centered on the junction, not a labeled box" do
        svg = renderer.render(layout_with_junction)
        svg_string = svg.to_s

        expect(svg_string).to include('id="junction-mid"')
        expect(svg_string).to include('cx="306.0"')
        expect(svg_string).to include('cy="46.0"')
        expect(svg_string).to include('r="6.0"')
        expect(svg_string).not_to include('id="service-mid"')
      end
    end

    context "with a cyclic group parent chain" do
      # group a(cloud)[A] in b / group b(cloud)[B] in a - grammar-valid
      # (nothing upstream validates that Group#parent_id chains
      # terminate), and ancestor_group_ids walks that chain. Without cycle
      # detection this loops forever; bounded here with a real timeout so
      # a regression fails fast instead of hanging the suite.
      def cyclic_groups_layout
        group_a = Sirena::Diagram::ArchitectureDiagram::Group.new(id: "a", label: "A", parent_id: "b")
        group_b = Sirena::Diagram::ArchitectureDiagram::Group.new(id: "b", label: "B", parent_id: "a")
        service1 = Sirena::Diagram::ArchitectureDiagram::Service.new(id: "s1", label: "S1", group_id: "a")
        service2 = Sirena::Diagram::ArchitectureDiagram::Service.new(id: "s2", label: "S2", group_id: "b")
        edge = Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "s1", to_id: "s2", from_position: "R",
                                                              to_position: "L")

        {
          services: {
            "s1" => { service: service1, x: 40, y: 40, width: 120, height: 80, group_id: "a" },
            "s2" => { service: service2, x: 200, y: 40, width: 120, height: 80, group_id: "b" },
          },
          groups: {
            "a" => { group: group_a, x: 10, y: 10, width: 300, height: 150 },
            "b" => { group: group_b, x: 10, y: 10, width: 300, height: 150 },
          },
          edges: [
            { edge: edge, from_x: 160, from_y: 80, to_x: 200, to_y: 80, from_side: "R", to_side: "L" },
          ],
          width: 400,
          height: 200,
        }
      end

      it "does not loop forever walking ancestor groups" do
        expect { Timeout.timeout(2) { renderer.render(cyclic_groups_layout) } }.not_to raise_error
      end
    end

    context "with an unrelated group sitting between two other groups' services" do
      # sA in gA, sB in gB, gMid sits directly between them and belongs to
      # neither endpoint's group - the shape obstacles_for's ancestor-group
      # exclusion has to get right: gA and gB are excluded (each edge
      # endpoint's own group), gMid is not. No existing spec built its
      # obstacles through ArchitectureRenderer#obstacles_for with a THIRD,
      # unrelated group actually in the way - the case-011 router spec
      # builds its obstacle list from services/junctions only, bypassing
      # obstacles_for's group handling entirely.
      def unrelated_group_layout
        group_a = Sirena::Diagram::ArchitectureDiagram::Group.new(id: "gA", label: "GA")
        group_b = Sirena::Diagram::ArchitectureDiagram::Group.new(id: "gB", label: "GB")
        group_mid = Sirena::Diagram::ArchitectureDiagram::Group.new(id: "gMid", label: "GMid")
        service_a = Sirena::Diagram::ArchitectureDiagram::Service.new(id: "sA", label: "A", group_id: "gA")
        service_b = Sirena::Diagram::ArchitectureDiagram::Service.new(id: "sB", label: "B", group_id: "gB")
        edge = Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "sA", to_id: "sB", from_position: "R",
                                                              to_position: "L")

        {
          services: {
            "sA" => { service: service_a, x: 40, y: 40, width: 60, height: 60, group_id: "gA" },
            "sB" => { service: service_b, x: 400, y: 40, width: 60, height: 60, group_id: "gB" },
          },
          groups: {
            "gA" => { group: group_a, x: 20, y: 20, width: 100, height: 100 },
            "gB" => { group: group_b, x: 380, y: 20, width: 100, height: 100 },
            "gMid" => { group: group_mid, x: 150, y: 20, width: 150, height: 100 },
          },
          edges: [
            { edge: edge, from_x: 100, from_y: 70, to_x: 400, to_y: 70, from_side: "R", to_side: "L" },
          ],
          width: 550,
          height: 200,
        }
      end

      def path_points(svg_string, edge_id)
        d_attribute = svg_string[/<g id="#{Regexp.escape(edge_id)}"[^>]*>.*?<path[^>]*\bd="([^"]*)"/m, 1]
        raise "no <path> found for edge #{edge_id}" if d_attribute.nil?

        d_attribute.scan(/-?\d+(?:\.\d+)?/).each_slice(2).map { |x, y| { x: x.to_f, y: y.to_f } }
      end

      def segment_crosses?(box, p1, p2)
        (0..200).any? do |i|
          t = i / 200.0
          x = p1[:x] + ((p2[:x] - p1[:x]) * t)
          y = p1[:y] + ((p2[:y] - p1[:y]) * t)
          x > box[:x] && x < box[:x] + box[:width] && y > box[:y] && y < box[:y] + box[:height]
        end
      end

      it "routes around the unrelated group's boundary" do
        layout = unrelated_group_layout
        svg_string = renderer.render(layout).to_s
        points = path_points(svg_string, "edge-sA-sB")
        g_mid = layout[:groups]["gMid"]

        crosses = points.each_cons(2).any? { |p1, p2| segment_crosses?(g_mid, p1, p2) }
        expect(crosses).to be(false)
      end
    end

    context "when the router raises for one edge" do
      # Tests the ISOLATION guarantee itself, not one specific bug that
      # happens to make the router raise - a stub proves route_edges
      # degrades gracefully regardless of why a future raise happens,
      # matching the router's own never-raise-from-#route philosophy one
      # layer up. Two edges: one the stub breaks, one it doesn't, so a
      # single bad edge is also proven not to take the rest down with it.
      def two_edge_layout
        service_a = Sirena::Diagram::ArchitectureDiagram::Service.new(id: "a", label: "A", group_id: nil)
        service_b = Sirena::Diagram::ArchitectureDiagram::Service.new(id: "b", label: "B", group_id: nil)
        service_c = Sirena::Diagram::ArchitectureDiagram::Service.new(id: "c", label: "C", group_id: nil)
        edge_ab = Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "a", to_id: "b", from_position: "R",
                                                                 to_position: "L")
        edge_bc = Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "b", to_id: "c", from_position: "R",
                                                                 to_position: "L")

        {
          services: {
            "a" => { service: service_a, x: 40, y: 40, width: 120, height: 80, group_id: :root },
            "b" => { service: service_b, x: 200, y: 40, width: 120, height: 80, group_id: :root },
            "c" => { service: service_c, x: 360, y: 40, width: 120, height: 80, group_id: :root },
          },
          groups: {},
          edges: [
            { edge: edge_ab, from_x: 160, from_y: 80, to_x: 200, to_y: 80, from_side: "R", to_side: "L" },
            { edge: edge_bc, from_x: 320, from_y: 80, to_x: 360, to_y: 80, from_side: "R", to_side: "L" },
          ],
          width: 520,
          height: 200,
        }
      end

      it "does not fail the whole render" do
        broken_router = instance_double(Sirena::Renderer::ArchitectureEdgeRouter)
        allow(broken_router).to receive(:route).and_raise("boom")
        allow(renderer).to receive(:edge_router).and_return(broken_router)

        expect { renderer.render(two_edge_layout) }.not_to raise_error
      end

      it "falls back to the straight line only for the edge that raised" do
        broken_router = instance_double(Sirena::Renderer::ArchitectureEdgeRouter)
        allow(broken_router).to receive(:route) do |from:, to:, obstacles:| # rubocop:disable Lint/UnusedBlockArgument
          raise "boom" if from[:box][:x] == 40 # only edge a->b

          [from[:point], to[:point]]
        end
        allow(renderer).to receive(:edge_router).and_return(broken_router)

        svg_string = renderer.render(two_edge_layout).to_s

        expect(svg_string).to include('id="edge-a-b"')
        expect(svg_string).to include('id="edge-b-c"')
      end

      it "does not fail the whole render when obstacles_for itself raises" do
        # obstacles_for's result is an ARGUMENT to routed_points - Ruby
        # evaluates arguments before the call, so a raise here happens
        # outside routed_points's own rescue unless routed_points computes
        # obstacles itself, inside the rescued scope.
        allow(renderer).to receive(:obstacles_for).and_raise("boom")

        expect { renderer.render(two_edge_layout) }.not_to raise_error
      end
    end

    context "with the B--T diagonal case" do
      # service a(server)[A] / service b(server)[B] / service c(server)[C]
      # a:R -- T:b. A straight line from a's R face to b's T face clips
      # through b's own interior - this is the second Done-criterion named
      # in the task, asserted at the layer that actually draws the path.
      let(:diagram_abc) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "a", label: "A", icon: "server", group_id: nil),
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "b", label: "B", icon: "server", group_id: nil),
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "c", label: "C", icon: "server", group_id: nil),
          ],
          groups: [],
          edges: [
            Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "a", to_id: "b", from_position: "R",
                                                           to_position: "T"),
          ]
        )
      end

      let(:layout_abc) do
        {
          services: {
            "a" => { service: diagram_abc.services[0], x: 40, y: 40, width: 120, height: 80, group_id: :root },
            "b" => { service: diagram_abc.services[1], x: 200, y: 40, width: 120, height: 80, group_id: :root },
            "c" => { service: diagram_abc.services[2], x: 360, y: 40, width: 120, height: 80, group_id: :root },
          },
          groups: {},
          edges: [
            { edge: diagram_abc.edges[0], from_x: 160, from_y: 80, to_x: 260, to_y: 40, from_side: "R", to_side: "T" },
          ],
          width: 520,
          height: 200,
        }
      end

      # a:R -- B:b needs the router's widened-margin retreat (arriving at a
      # bottom face means approaching from BELOW everything else, and
      # nothing in this two-box diagram sits lower than the boxes'
      # own bottom edge) - with width/height set exactly to the boxes'
      # own extent (no slack at all), the routed point at y=140 genuinely
      # exceeds a layout sized only from node positions. This is what
      # actually distinguishes the canvas-sizing fix from a fixture that
      # happens to have enough padding regardless.
      def layout_ab_tight
        diagram = Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "a", label: "A", icon: "server", group_id: nil),
            Sirena::Diagram::ArchitectureDiagram::Service.new(id: "b", label: "B", icon: "server", group_id: nil),
          ],
          groups: [],
          edges: [
            Sirena::Diagram::ArchitectureDiagram::Edge.new(from_id: "a", to_id: "b", from_position: "R",
                                                           to_position: "B"),
          ]
        )

        {
          services: {
            "a" => { service: diagram.services[0], x: 40, y: 40, width: 120, height: 80, group_id: :root },
            "b" => { service: diagram.services[1], x: 200, y: 40, width: 120, height: 80, group_id: :root },
          },
          groups: {},
          edges: [
            { edge: diagram.edges[0], from_x: 160, from_y: 80, to_x: 260, to_y: 120, from_side: "R", to_side: "B" },
          ],
          width: 320,
          height: 120,
        }
      end

      # The path's `d` lives on the <path> inside the <g id="edge-..."> the
      # edge is grouped under - not on the group tag itself.
      def path_points(svg_string, edge_id)
        d_attribute = svg_string[/<g id="#{Regexp.escape(edge_id)}"[^>]*>.*?<path[^>]*\bd="([^"]*)"/m, 1]
        raise "no <path> found for edge #{edge_id}" if d_attribute.nil?

        d_attribute.scan(/-?\d+(?:\.\d+)?/).each_slice(2).map { |x, y| { x: x.to_f, y: y.to_f } }
      end

      def segment_crosses_rectangle?(p1, p2, rect)
        (0..200).any? do |i|
          t = i / 200.0
          x = p1[:x] + ((p2[:x] - p1[:x]) * t)
          y = p1[:y] + ((p2[:y] - p1[:y]) * t)
          x > rect[:x] && x < rect[:x] + rect[:width] && y > rect[:y] && y < rect[:y] + rect[:height]
        end
      end

      it "draws around b instead of through it" do
        svg = renderer.render(layout_abc)
        points = path_points(svg.to_s, "edge-a-b")
        b = layout_abc[:services]["b"]

        crosses = points.each_cons(2).any? { |p1, p2| segment_crosses_rectangle?(p1, p2, b) }
        expect(crosses).to be(false)
      end

      it "keeps every routed point within the document's own bounds" do
        svg = renderer.render(layout_ab_tight)
        points = path_points(svg.to_s, "edge-a-b")

        points.each do |point|
          expect(point[:x]).to be_between(0, svg.width)
          expect(point[:y]).to be_between(0, svg.height)
        end
      end
    end

    context "with every case in the architecture corpus" do
      # Generalizes the 42-instance edge-crosses-box sweep from the plan
      # (5 of 22 parseable cases) into a suite assertion: every parseable
      # .mmd renders with no edge's path crossing a service or junction
      # that is not its own endpoint. This sweep checks node boxes only -
      # group-boundary avoidance (obstacles_for's ancestor-group exclusion)
      # is covered separately, by "with an unrelated group sitting between
      # two other groups' services" above, which is the one spec that
      # actually goes through ArchitectureRenderer#obstacles_for's group
      # handling; the corpus here never asserts against a group box.
      def path_points(svg_string, edge_id)
        d_attribute = svg_string[/<g id="#{Regexp.escape(edge_id)}"[^>]*>.*?<path[^>]*\bd="([^"]*)"/m, 1]
        raise "no <path> found for edge #{edge_id}" if d_attribute.nil?

        d_attribute.scan(/-?\d+(?:\.\d+)?/).each_slice(2).map { |x, y| { x: x.to_f, y: y.to_f } }
      end

      def segment_crosses?(box, p1, p2)
        (0..200).any? do |i|
          t = i / 200.0
          x = p1[:x] + ((p2[:x] - p1[:x]) * t)
          y = p1[:y] + ((p2[:y] - p1[:y]) * t)
          x > box[:x] && x < box[:x] + box[:width] && y > box[:y] && y < box[:y] + box[:height]
        end
      end

      Dir.glob(File.expand_path("../../mermaid/architecture/*.mmd", __dir__)).each do |path|
        it "#{File.basename(path)}: no edge crosses a non-endpoint service or junction" do
          diagram = begin
            Sirena::Parser::Architecture.new.parse(File.read(path))
          rescue StandardError
            skip "does not parse - out of scope for this task"
          end

          layout = Sirena::Transform::ArchitectureTransform.new.to_graph(diagram)
          svg_string = renderer.render(layout).to_s
          nodes = layout[:services].merge(layout[:junctions])

          layout[:edges].each do |edge_info|
            edge = edge_info[:edge]
            edge_id = "edge-#{edge.from_id}-#{edge.to_id}"
            points = path_points(svg_string, edge_id)

            nodes.each do |id, box|
              next if id == edge.from_id || id == edge.to_id

              crosses = points.each_cons(2).any? { |p1, p2| segment_crosses?(box, p1, p2) }
              expect(crosses).to be(false), "#{edge_id} crosses #{id} in #{File.basename(path)}"
            end
          end
        end
      end
    end
  end
end