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
  end
end
