# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/pie"
require "sirena/layout/pie"
require "sirena/renderer/pie"

RSpec.describe Sirena::Parser::Pie do
  let(:parser) { described_class.new }
  let(:transform) { Sirena::Layout::Pie.new }
  let(:renderer) { Sirena::Renderer::Pie.new }

  describe "#parse" do
    context "with simple pie chart" do
      let(:source) do
        <<~MERMAID
          pie
                "Apples": 42
                "Oranges": 58
        MERMAID
      end

      let(:expected_slices) do
        [
          have_attributes(label: "Apples", value: 42.0),
          have_attributes(label: "Oranges", value: 58.0),
        ]
      end

      it "parses successfully" do
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Pie)
          .and have_attributes(slices: expected_slices)
      end
    end

    context "with title" do
      let(:source) do
        <<~MERMAID
          pie title Sales Distribution
                "Product A": 45
                "Product B": 55
        MERMAID
      end

      it "parses title correctly" do
        diagram = parser.parse(source)
        expect(diagram).to have_attributes(
          title: "Sales Distribution", slices: have_attributes(length: 2),
        )
      end
    end

    context "with showData flag" do
      let(:source) do
        <<~MERMAID
          pie showData
                "Category A": 100
                "Category B": 50
        MERMAID
      end

      it "sets show_data flag" do
        diagram = parser.parse(source)
        expect(diagram).to have_attributes(
          show_data: true, slices: have_attributes(length: 2),
        )
      end
    end

    context "with comments" do
      let(:source) do
        <<~MERMAID
          pie
                %% This is a comment
                "Item 1": 30
                "Item 2": 70
        MERMAID
      end

      it "ignores comments" do
        diagram = parser.parse(source)
        expect(diagram.slices.length).to eq(2)
      end
    end

    context "with accessibility features" do
      let(:source) do
        <<~MERMAID
          pie title Sales Chart
                accTitle: Accessible Title
                accDescr: This chart shows sales distribution
                "Q1": 25
                "Q2": 75
        MERMAID
      end

      it "parses accessibility attributes" do
        expect(parser.parse(source)).to have_attributes(
          title: "Sales Chart",
          acc_title: "Accessible Title",
          acc_description: "This chart shows sales distribution",
        )
      end
    end

    context "with decimal values" do
      let(:source) do
        <<~MERMAID
          pie
                "First": 42.5
                "Second": 57.5
        MERMAID
      end

      it "handles decimal values" do
        diagram = parser.parse(source)
        expect(diagram.slices.map(&:value)).to eq([42.5, 57.5])
      end
    end

    context "with negative values" do
      let(:source) do
        <<~MERMAID
          pie
                "Positive": 100
                "Negative": -50
        MERMAID
      end

      it "handles negative values" do
        diagram = parser.parse(source)
        expect(diagram.slices[1].value).to eq(-50.0)
      end
    end

    context "with empty diagram" do
      let(:source) { "pie" }

      it "parses empty diagram" do
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Pie)
          .and have_attributes(slices: be_empty)
          .and be_valid
      end
    end

    context "with case-insensitive pie keyword" do
      it 'parses "Pie Chart"' do
        diagram = parser.parse("Pie Chart")
        expect(diagram).to be_a(Sirena::Diagram::Pie)
      end

      it 'parses "pie chart"' do
        diagram = parser.parse("pie chart")
        expect(diagram).to be_a(Sirena::Diagram::Pie)
      end

      it 'parses "pie"' do
        diagram = parser.parse("pie")
        expect(diagram).to be_a(Sirena::Diagram::Pie)
      end
    end
  end

  describe "transform and render pipeline" do
    subject(:svg) { renderer.render(scene) }

    let(:source) do
      <<~MERMAID
        pie title Product Distribution
              "Product A": 45
              "Product B": 30
              "Product C": 25
      MERMAID
    end

    let(:scene) { transform.to_graph(parser.parse(source)) }

    it "produces valid SVG output" do
      expect(svg).to be_a(Sirena::Svg::Document).and have_attributes(
        width: be > 0, height: be > 0, children: satisfy(&:any?),
      )
    end

    it "calculates correct percentages and angles" do
      values = [scene.slices.map(&:percentage), scene.slices.sum(&:angle)]
      expect(values).to match([[45.0, 30.0, 25.0], be_within(0.1).of(360.0)])
    end
  end
end
