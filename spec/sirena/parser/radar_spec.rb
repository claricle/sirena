# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/radar"

RSpec.describe Sirena::Parser::RadarParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with simple radar" do
      it "parses a simple radar with axes and curve" do
        source = <<~MERMAID
          radar-beta
              axis A,B,C
              curve mycurve{1,2,3}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::RadarChart)
        expect(diagram.axes.size).to eq(3)
        expect(diagram.axes.map(&:id)).to eq(["A", "B", "C"])
        expect(diagram.curves.size).to eq(1)
        expect(diagram.curves.first.id).to eq("mycurve")
      end

      it "parses axes with labels" do
        source = <<~MERMAID
          radar-beta
              axis A["Axis A"], B["Axis B"] ,C["Axis C"]
              curve mycurve{1,2,3}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.axes.size).to eq(3)
        expect(diagram.axes[0].label).to eq("Axis A")
        expect(diagram.axes[1].label).to eq("Axis B")
        expect(diagram.axes[2].label).to eq("Axis C")
      end
    end

    context "with title and metadata" do
      it "parses title" do
        source = <<~MERMAID
          radar-beta
              title Radar diagram
              axis A, B, C
              curve c1{1, 2, 3}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq("Radar diagram")
      end

      it "parses accessibility metadata" do
        source = <<~MERMAID
          radar-beta
              title Radar diagram
              accTitle: Radar accTitle
              accDescr: Radar accDescription
              axis A, B, C
              curve c1{1,2,3}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq("Radar diagram")
        expect(diagram.acc_title).to eq("Radar accTitle")
        expect(diagram.acc_descr).to eq("Radar accDescription")
      end
    end

    context "with curve values" do
      it "parses positional values" do
        source = <<~MERMAID
          radar-beta
              axis A,B,C
              curve mycurve{1,2,3}
        MERMAID

        diagram = parser.parse(source)
        curve = diagram.curves.first
        expect(curve.value_for("A")).to eq(1.0)
        expect(curve.value_for("B")).to eq(2.0)
        expect(curve.value_for("C")).to eq(3.0)
      end

      it "parses named values" do
        source = <<~MERMAID
          radar-beta
              axis A,B,C
              curve mycurve{ C: 3, A: 1, B: 2 }
        MERMAID

        diagram = parser.parse(source)
        curve = diagram.curves.first
        expect(curve.value_for("A")).to eq(1.0)
        expect(curve.value_for("B")).to eq(2.0)
        expect(curve.value_for("C")).to eq(3.0)
      end

      it "parses curve with label" do
        source = <<~MERMAID
          radar-beta
              axis A,B,C
              curve mycurve["My Curve"]{1,2,3}
        MERMAID

        diagram = parser.parse(source)
        curve = diagram.curves.first
        expect(curve.id).to eq("mycurve")
        expect(curve.label).to eq("My Curve")
      end
    end

    context "with multiple curves" do
      it "parses multiple curves" do
        source = <<~MERMAID
          radar-beta
              axis A, B, C
              curve mycurve["My Curve"]{1,2,3}
              curve mycurve2["My Curve 2"]{ C: 1, A: 2, B: 3 }
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.curves.size).to eq(2)
        expect(diagram.curves[0].label).to eq("My Curve")
        expect(diagram.curves[1].label).to eq("My Curve 2")
      end
    end

    context "with options" do
      it "parses ticks option" do
        source = <<~MERMAID
          radar-beta
              ticks 10
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.options[:ticks]).to eq(10)
      end

      it "parses showLegend option" do
        source = <<~MERMAID
          radar-beta
              showLegend false
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.options[:show_legend]).to eq(false)
      end

      it "parses graticule option" do
        source = <<~MERMAID
          radar-beta
              graticule polygon
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.options[:graticule]).to eq("polygon")
      end

      it "parses min and max options" do
        source = <<~MERMAID
          radar-beta
              min 1
              max 10
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.options[:min]).to eq(1.0)
        expect(diagram.options[:max]).to eq(10.0)
      end

      it "parses multiple options" do
        source = <<~MERMAID
          radar-beta
              ticks 10
              showLegend false
              graticule polygon
              min 1
              max 10
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.options[:ticks]).to eq(10)
        expect(diagram.options[:show_legend]).to eq(false)
        expect(diagram.options[:graticule]).to eq("polygon")
        expect(diagram.options[:min]).to eq(1.0)
        expect(diagram.options[:max]).to eq(10.0)
      end
    end

    context "with comments" do
      it "parses diagram with comments" do
        source = <<~MERMAID
          radar-beta
              %% This is a comment
              axis A,B,C
              %% This is another comment
              curve mycurve{1,2,3}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.axes.size).to eq(3)
        expect(diagram.curves.size).to eq(1)
      end
    end

    context "with complex example" do
      it "parses a full radar diagram" do
        source = <<~MERMAID
          radar-beta
              title Radar diagram
              accTitle: Radar accTitle
              accDescr: Radar accDescription
              axis A["Axis A"], B["Axis B"] ,C["Axis C"]
              curve mycurve["My Curve"]{1,2,3}
              curve mycurve2["My Curve 2"]{ C: 1, A: 2, B: 3 }
              graticule polygon
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq("Radar diagram")
        expect(diagram.acc_title).to eq("Radar accTitle")
        expect(diagram.acc_descr).to eq("Radar accDescription")
        expect(diagram.axes.size).to eq(3)
        expect(diagram.curves.size).to eq(2)
        expect(diagram.options[:graticule]).to eq("polygon")
      end
    end
  end
end