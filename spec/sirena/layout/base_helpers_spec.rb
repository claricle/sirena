# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Base do
  subject(:layout) do
    Class.new(described_class) do
      public :build_elk_options, :calculate_node_dimensions, :measure_text,
             :node_padding
    end.new
  end

  describe "helper contracts" do
    it "reports the concrete layout class when build_graph is not implemented" do
      expect { layout.build_graph(Object.new) }
        .to raise_error(NotImplementedError, /must implement #build_graph\(diagram\)/)
    end

    it "passes every text measurement option through" do
      allow(Sirena::TextMeasurement).to receive(:measure).and_return(width: 12, height: 8)

      layout.measure_text("code", font_size: 13, width: 30, height: 20, monospace: true)

      expect(Sirena::TextMeasurement).to have_received(:measure).with(
        "code", font_size: 13, width: 30, height: 20, monospace: true,
      )
    end

    it "combines layered defaults with caller overrides" do
      options = layout.build_elk_options(
        direction: described_class::DIRECTION_LEFT,
        described_class::ElkOptions::NODE_NODE_SPACING => 12,
      )

      expect(options).to include(
        "elk.algorithm" => "layered",
        "elk.direction" => "LEFT",
        "elk.spacing.nodeNode" => 12,
        "elk.layered.nodePlacement.strategy" => "SIMPLE",
      )
    end

    it "adds force defaults for both force-based algorithms" do
      options = %w[stress force].map do |algorithm|
        layout.build_elk_options(algorithm: algorithm)
      end

      expect(options).to all(include(
        "elk.spacing.nodeNode" => 75.0,
        "elk.spacing.edgeNode" => 30,
        "elk.spacing.edgeEdge" => 30,
      ))
    end

    it "leaves non-layered non-force algorithms free of unrelated defaults" do
      options = layout.build_elk_options(
        algorithm: described_class::ALGORITHM_MRTREE,
        custom: "kept",
      )

      expect(options).to eq(
        "elk.algorithm" => "mrtree",
        "elk.direction" => "DOWN",
        custom: "kept",
      )
    end

    it "returns the padding contract for every supported shape and fallback" do
      padding = %i[rect circle diamond unknown].to_h do |shape|
        [shape, layout.node_padding(shape)]
      end

      expect(padding).to eq(
        rect: { top: 10, bottom: 10, left: 15, right: 15 },
        circle: { top: 15, bottom: 15, left: 15, right: 15 },
        diamond: { top: 20, bottom: 20, left: 20, right: 20 },
        unknown: { top: 10, bottom: 10, left: 10, right: 10 },
      )
    end

    it "adds the selected shape padding to content dimensions" do
      dimensions = layout.calculate_node_dimensions(30, 20, :diamond)

      expect(dimensions).to eq(width: 70, height: 60)
    end
  end
end
