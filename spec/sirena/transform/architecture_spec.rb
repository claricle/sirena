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
  end
end
