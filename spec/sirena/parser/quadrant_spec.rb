# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/quadrant"

RSpec.describe Sirena::Parser::Quadrant do
  let(:parser) { described_class.new }

  context "when parsing a simple quadrant chart" do
    let(:source) do
      <<~QUADRANT
        quadrantChart
          title Product Analysis
          x-axis Low Cost --> High Cost
          y-axis Low Value --> High Value
          quadrant-1 Invest
          quadrant-2 Evaluate
          quadrant-3 Divest
          quadrant-4 Maintain
          Product A: [0.3, 0.7]
      QUADRANT
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram" do
      expect(diagram).to be_a(Sirena::Diagram::Quadrant)
    end

    it "retains diagram.title" do
      expect(diagram.title).to eq("Product Analysis")
    end

    it "retains diagram.x_axis_left" do
      expect(diagram.x_axis_left).to eq("Low Cost")
    end

    it "retains diagram.x_axis_right" do
      expect(diagram.x_axis_right).to eq("High Cost")
    end

    it "retains diagram.y_axis_bottom" do
      expect(diagram.y_axis_bottom).to eq("Low Value")
    end

    it "retains diagram.y_axis_top" do
      expect(diagram.y_axis_top).to eq("High Value")
    end

    it "retains diagram.quadrant_1_label" do
      expect(diagram.quadrant_1_label).to eq("Invest")
    end

    it "retains diagram.quadrant_2_label" do
      expect(diagram.quadrant_2_label).to eq("Evaluate")
    end

    it "retains diagram.quadrant_3_label" do
      expect(diagram.quadrant_3_label).to eq("Divest")
    end

    it "retains diagram.quadrant_4_label" do
      expect(diagram.quadrant_4_label).to eq("Maintain")
    end

    it "retains diagram.points.length" do
      expect(diagram.points.length).to eq(1)
    end

    it "retains diagram.points.first.label" do
      expect(diagram.points.first.label).to eq("Product A")
    end

    it "retains diagram.points.first.x" do
      expect(diagram.points.first.x).to eq(0.3)
    end

    it "retains diagram.points.first.y" do
      expect(diagram.points.first.y).to eq(0.7)
    end
  end

  context "when parsing quadrant chart with multiple points" do
    let(:source) do
      <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Point A: [0.2, 0.8]
          Point B: [0.7, 0.3]
          Point C: [0.5, 0.5]
      QUADRANT
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.points.length" do
      expect(diagram.points.length).to eq(3)
    end

    it "retains diagram.points 0 .label" do
      expect(diagram.points[0].label).to eq("Point A")
    end

    it "retains diagram.points 1 .label" do
      expect(diagram.points[1].label).to eq("Point B")
    end

    it "retains diagram.points 2 .label" do
      expect(diagram.points[2].label).to eq("Point C")
    end
  end

  context "when parsing points with styling parameters" do
    let(:source) do
      <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Product A: [0.5, 0.5] radius: 10
          Product B: [0.3, 0.7] radius: 8, color: #ff0000
          Product C: [0.8, 0.2] radius: 12, color: #00ff00, stroke-color: #0000ff
          Product D: [0.1, 0.9] radius: 10, color: #ff0000, stroke-color: #00ff00, stroke-width: 3px
      QUADRANT
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.points.length" do
      expect(diagram.points.length).to eq(4)
    end

    it "retains diagram.points 0 .radius" do
      expect(diagram.points[0].radius).to eq(10.0)
    end

    it "retains diagram.points 1 .radius" do
      expect(diagram.points[1].radius).to eq(8.0)
    end

    it "retains diagram.points 1 .color" do
      expect(diagram.points[1].color).to eq("#ff0000")
    end

    it "retains diagram.points 2 .radius" do
      expect(diagram.points[2].radius).to eq(12.0)
    end

    it "retains diagram.points 2 .color" do
      expect(diagram.points[2].color).to eq("#00ff00")
    end

    it "retains diagram.points 2 .stroke_color" do
      expect(diagram.points[2].stroke_color).to eq("#0000ff")
    end

    it "retains diagram.points 3 .radius" do
      expect(diagram.points[3].radius).to eq(10.0)
    end

    it "retains diagram.points 3 .color" do
      expect(diagram.points[3].color).to eq("#ff0000")
    end

    it "retains diagram.points 3 .stroke_color" do
      expect(diagram.points[3].stroke_color).to eq("#00ff00")
    end

    it "retains diagram.points 3 .stroke_width" do
      expect(diagram.points[3].stroke_width).to eq(3.0)
    end
  end

  context "when parsing quoted axis labels" do
    let(:source) do
      <<~QUADRANT
        quadrantChart
          x-axis "Low Cost ❤" --> "High Cost"
          y-axis "Low Value" --> "High Value"
          Product: [0.5, 0.5]
      QUADRANT
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.x_axis_left" do
      expect(diagram.x_axis_left).to eq("Low Cost ❤")
    end

    it "retains diagram.x_axis_right" do
      expect(diagram.x_axis_right).to eq("High Cost")
    end
  end

  context "when parsing minimal quadrant chart with just header" do
    let(:source) do
      <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
      QUADRANT
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram" do
      expect(diagram).to be_a(Sirena::Diagram::Quadrant)
    end

    it "retains diagram.points" do
      expect(diagram.points).to be_empty
    end
  end

  context "when validates diagram structure" do
    let(:source) do
      <<~QUADRANT
        quadrantChart
          title Campaign Analysis
          x-axis Low Reach --> High Reach
          y-axis Low Engagement --> High Engagement
          Campaign A: [0.3, 0.6]
      QUADRANT
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.valid" do
      expect(diagram.valid?).to be true
    end
  end

  context "when determines point quadrants correctly" do
    let(:source) do
      <<~QUADRANT
        quadrantChart
          x-axis Left --> Right
          y-axis Bottom --> Top
          Q1 Point: [0.7, 0.7]
          Q2 Point: [0.3, 0.7]
          Q3 Point: [0.3, 0.3]
          Q4 Point: [0.7, 0.3]
      QUADRANT
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.points 0 .quadrant" do
      expect(diagram.points[0].quadrant).to eq(1)
    end

    it "retains diagram.points 1 .quadrant" do
      expect(diagram.points[1].quadrant).to eq(2)
    end

    it "retains diagram.points 2 .quadrant" do
      expect(diagram.points[2].quadrant).to eq(3)
    end

    it "retains diagram.points 3 .quadrant" do
      expect(diagram.points[3].quadrant).to eq(4)
    end
  end

  # :corpus - sweeps the whole fixture directory and only asserts
  # `not_to raise_error`. Runs in `spec:corpus`, isolated from the
  # coverage-collecting `spec:unit` run: see .simplecov and
  # tasks/coverage.rake.
  describe "fixture files", :corpus do
    pattern = File.expand_path("../../mermaid/quadrant/*.mmd", __dir__)
    rejected = "should_be_able_to_handle_constructor_as_a_classn-0901aef7.mmd"
    Dir.glob(pattern).each do |fixture_file|
      next if File.basename(fixture_file) == rejected

      it "parses #{File.basename(fixture_file)}" do
        source = File.read(fixture_file)

        expect { parser.parse(source) }.not_to raise_error
      end
    end

    context "when refusing the oracle-rejected fixture with a fill class " \
            "style" do
      let(:source) { File.read(path) }
      let(:path) do
        File.expand_path("../../mermaid/quadrant/#{filename}", __dir__)
      end
      let(:filename) do
        "should_be_able_to_handle_constructor_as_a_classn-0901aef7.mmd"
      end

      it "rejects the invalid source" do
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError, /fill is not/)
      end
    end
  end
end
