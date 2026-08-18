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

    context "with the curve value-block constructs corpus case 003 uses" do
      it "parses a curve with a space before the value block" do
        source = <<~MERMAID
          radar-beta
              axis A, B, C
              curve c1 {3, 2, 1}
        MERMAID

        diagram = parser.parse(source)
        curve = diagram.curves.first
        expect(curve.value_for("A")).to eq(3.0)
        expect(curve.value_for("C")).to eq(1.0)
      end

      it "parses named values without colons" do
        source = <<~MERMAID
          radar-beta
              axis A, B
              curve c1{A 1, B 2}
        MERMAID

        diagram = parser.parse(source)
        curve = diagram.curves.first
        expect(curve.value_for("A")).to eq(1.0)
        expect(curve.value_for("B")).to eq(2.0)
      end

      it "parses a value block spanning multiple lines" do
        source = <<~MERMAID
          radar-beta
              axis A, B, C
              curve c1{
                  A: 1, B: 2,
                  C: 3
              }
        MERMAID

        diagram = parser.parse(source)
        curve = diagram.curves.first
        expect(curve.value_for("A")).to eq(1.0)
        expect(curve.value_for("B")).to eq(2.0)
        expect(curve.value_for("C")).to eq(3.0)
      end

      # A one-axis statement yields a Hash rather than an Array, and
      # Kernel#Array turns a Hash into its key/value pairs. Assignment used
      # to hide that because a later statement overwrote it; accumulating
      # keeps it, and the renderer then dies on a Symbol index. Every
      # existing example here used multi-axis statements, which is why the
      # regression got through.
      it "accumulates a single-axis statement into a later one" do
        source = <<~MERMAID
          radar-beta
              axis A
              axis B, C
              curve c1{1, 2, 3}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.axes.map(&:id)).to eq(["A", "B", "C"])
      end

      it "accumulates axes across multiple axis statements" do
        source = <<~MERMAID
          radar-beta
              axis A, B, C
              axis D["Dee"], E["Ee"]
              curve c1{1, 2, 3, 4, 5}
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.axes.map(&:id)).to eq(["A", "B", "C", "D", "E"])
        expect(diagram.axes.map(&:label))
          .to eq(["A", "B", "C", "Dee", "Ee"])
        # Every position, so a mis-mapping across the two statements
        # cannot hide behind a single spot check.
        expect(diagram.curves.first.values)
          .to eq("A" => 1.0, "B" => 2.0, "C" => 3.0, "D" => 4.0, "E" => 5.0)
      end

      it "parses the full corpus case" do
        source = File.read(
          File.expand_path(
            "../../mermaid/radar/003_rendering_radar_spec_radar_2.mmd",
            __dir__
          )
        )

        diagram = parser.parse(source)
        expect(diagram.title).to eq("My favorite ninjas")
        expect(diagram.axes.map(&:id))
          .to eq(["Agility", "Speed", "Strength", "Stam", "Intel"])
        expect(diagram.curves.map(&:id)).to eq(["Ninja1", "Ninja2", "Ninja3"])
        expect(diagram.curves[0].values)
          .to eq("Agility" => 2.0, "Speed" => 2.0, "Strength" => 3.0,
                 "Stam" => 5.0, "Intel" => 0.0)
        expect(diagram.curves[1].values)
          .to eq("Agility" => 2.0, "Speed" => 3.0, "Strength" => 4.0,
                 "Stam" => 1.0, "Intel" => 5.0)
        expect(diagram.curves[2].values)
          .to eq("Agility" => 3.0, "Speed" => 2.0, "Strength" => 1.0,
                 "Stam" => 5.0, "Intel" => 4.0)
        expect(diagram.options).to include(
          show_legend: true, ticks: 3, max: 8.0, min: 0.0,
          graticule: "polygon"
        )
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