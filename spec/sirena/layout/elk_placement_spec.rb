# frozen_string_literal: true

require "spec_helper"

module ElkPlacementSpecHelpers
  def source
    "flowchart TD\n A[Start] --> B{Ok?}\n B --> C[Go]\n B --> D[Stop]\n"
  end

  def graph_for(source, direction: nil)
    diagram = Sirena::Parser::Flowchart.new.parse(source)
    diagram.direction = direction if direction
    Sirena::Layout::Flowchart.new.send(:build_graph, diagram)
  end

  def positions(graph)
    graph[:children].to_h { |node| [node[:id], node.values_at(:x, :y)] }
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

    it "refuses a direction elkrb cannot lay out" do
      graph = graph_for("flowchart LR\n A-->B\n")
      expect { described_class.apply(graph) }
        .to raise_error(Sirena::Layout::LayoutError, /direction RIGHT/)
    end

    it "does not fall back to Grid when elkrb raises" do
      allow(Elkrb).to receive(:layout).and_raise(Elkrb::Error, "boom")
      expect { described_class.apply(graph_for(source)) }
        .to raise_error(Sirena::Layout::LayoutError, /boom/)
    end
  end

  describe "Engine#render with layout_engine: :elk" do
    it "renders a flowchart whose coordinates differ from the grid's" do
      elk = Sirena::Engine.new.render(source, layout_engine: :elk)
      expect(elk).not_to eq(Sirena::Engine.new.render(source))
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
