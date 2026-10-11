# frozen_string_literal: true

require "spec_helper"

module ElkPlacementSpecHelpers
  def source
    "flowchart TD\n A[Start] --> B{Ok?}\n B --> C[Go]\n B --> D[Stop]\n"
  end

  def graph_for(source, direction: nil)
    diagram = Sirena::Parser::Flowchart.new.parse(source)
    diagram.direction = direction if direction
    graph = Sirena::Notation::Mermaid::IRAdapters::Flowchart.call(diagram)
    Sirena::Layout::Flowchart.new.send(:build_graph, graph)
  end

  def positions(graph)
    graph[:children].to_h { |node| [node[:id], node.values_at(:x, :y)] }
  end

  def routed_edge_semantics(graph)
    graph[:edges].map do |edge|
      [edge[:id], edge[:labels], edge[:metadata], edge[:sections]&.any?]
    end
  end

  def expected_routed_edge_semantics(graph)
    graph[:edges].map do |edge|
      [edge[:id], edge[:labels], edge[:metadata], true]
    end
  end

  def render_counting_placements(**)
    calls = 0
    allow(Sirena::Layout::ElkPlacement).to receive(:apply)
      .and_wrap_original do |original, *args|
        calls += 1
        original.call(*args)
      end
    [Sirena::Engine.new.render(source, **), calls]
  end
end

RSpec.describe Sirena::Layout::ElkPlacement do
  include ElkPlacementSpecHelpers

  describe ".apply" do
    it "positions every node, nested ones included" do
      graph = graph_for("flowchart TD\n subgraph S\n A-->B\n end\n")
      described_class.apply(graph)
      inner = graph[:children].first[:children]
      expect(inner.map { |node| node[:x] }).to all(be_a(Float))
    end

    it "places nodes differently from Grid" do
      elk = described_class.apply(graph_for(source))
      grid = Sirena::Layout::Grid.apply(graph_for(source))
      expect(positions(elk)).not_to eq(positions(grid))
    end

    it "puts a successor in a lower layer" do
      placed = positions(described_class.apply(graph_for(source)))
      expect(placed["B"][1]).to be > placed["A"][1]
    end

    it "copies the routes returned by elkrb without replacing edge semantics" do
      graph = graph_for("flowchart TD\n A-->|first|B\n B-->|second|C\n")
      expected = expected_routed_edge_semantics(graph)
      described_class.apply(graph)
      expect(routed_edge_semantics(graph)).to eq(expected)
    end

    it "copies every route when parallel edges share a semantic id" do
      graph = graph_for("flowchart TD\n A-->B\n A-->B\n")
      ids = graph[:edges].map { |edge| edge[:id] }
      described_class.apply(graph)

      routed = graph[:edges].all? { |edge| edge[:sections]&.any? }
      expect([ids.uniq.size, routed]).to eq([1, true])
    end

    it "refuses an unsupported direction" do
      graph = graph_for("flowchart TD\n A-->B\n")
      key = Sirena::Layout::Base::ElkOptions::DIRECTION
      graph[:layoutOptions][key] = "SIDEWAYS"
      expect { described_class.apply(graph) }
        .to raise_error(Sirena::Layout::LayoutError, /direction SIDEWAYS/)
    end

    it "does not fall back to Grid when elkrb raises" do
      allow(Elkrb).to receive(:layout).and_raise(Elkrb::Error, "boom")
      expect { described_class.apply(graph_for(source)) }
        .to raise_error(Sirena::Layout::LayoutError, /boom/)
    end
  end

  describe "Engine#render with layout_engine: :elk" do
    it "places a class diagram differently from the grid default" do
      class_source = "classDiagram\n A <|-- B\n A <|-- C\n A <|-- D\n"
      elk = Sirena::Engine.new.render(class_source, layout_engine: :elk)
      expect(elk).not_to eq(Sirena::Engine.new.render(class_source))
    end

    it "places a flowchart through ElkPlacement with or without the option" do
      explicit, explicit_calls = render_counting_placements(layout_engine: :elk)
      default, default_calls = render_counting_placements

      expect([explicit_calls, default_calls, default])
        .to eq([1, 1, explicit])
    end

    it "retains a self-loop for Flowchart to route after elkrb placement" do
      svg = Sirena::Engine.new.render("flowchart TD\n A --> A\n",
                                      layout_engine: :elk)
      group = svg[%r{<g id="edge-A_to_A".*?</g>}m]
      path = group[/<path\b[^>]*\bd="([^"]+)"/, 1]

      expect(path.scan(/\bL /).size).to be >= 3
    end

    it "raises for a diagram type without an elk placement" do
      pie = "pie\n \"a\" : 1\n"
      expect { Sirena::Engine.new.render(pie, layout_engine: :elk) }
        .to raise_error(Sirena::Layout::LayoutError, /not available/)
    end

    it "rejects an unknown engine name" do
      expect { Sirena::Engine.new.render(source, layout_engine: :dagre) }
        .to raise_error(Sirena::Engine::PipelineError, /layout_engine/)
    end
  end
end
