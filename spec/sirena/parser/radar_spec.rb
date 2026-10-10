# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/radar"

RSpec.describe Sirena::Parser::Radar do
  let(:parser) { described_class.new }

  def self.radar_case(source, expected, &actual)
    proc do
      diagram = parser.parse(source)
      expect(instance_exec(diagram, &actual)).to eq(expected)
    end
  end

  def self.radar_example(description, source, expected, &actual)
    it(description, &radar_case(source, expected, &actual))
  end

  describe "#parse" do
    context "with simple radar" do
      it(
        "parses a simple radar with axes and curve",
        &radar_case(
          <<~MERMAID,
            radar-beta
                axis A,B,C
                curve mycurve{1,2,3}
          MERMAID
          [Sirena::Diagram::Radar, 3, %w[A B C], 1, "mycurve"],
        ) do |diagram|
          [diagram.class, diagram.axes.size, diagram.axes.map(&:id),
           diagram.curves.size, diagram.curves.first.id]
        end
      )

      radar_example(
        "parses axes with labels",
        <<~MERMAID,
          radar-beta
              axis A["Axis A"], B["Axis B"] ,C["Axis C"]
              curve mycurve{1,2,3}
        MERMAID
        [3, "Axis A", "Axis B", "Axis C"],
      ) do |diagram|
        [diagram.axes.size, *diagram.axes.map(&:label)]
      end
    end

    context "with title and metadata" do
      it(
        "parses title",
        &radar_case(
          <<~MERMAID,
            radar-beta
                title Radar diagram
                axis A, B, C
                curve c1{1, 2, 3}
          MERMAID
          "Radar diagram",
          &:title
        )
      )

      radar_example(
        "parses accessibility metadata",
        <<~MERMAID,
          radar-beta
              title Radar diagram
              accTitle: Radar accTitle
              accDescr: Radar accDescription
              axis A, B, C
              curve c1{1,2,3}
        MERMAID
        ["Radar diagram", "Radar accTitle", "Radar accDescription"],
      ) do |diagram|
        [diagram.title, diagram.acc_title, diagram.acc_descr]
      end
    end

    context "with only comments" do
      it "reads a body of only comments and blank lines as empty" do
        diagram = parser.parse("radar-beta\n%% only a comment\n\n")

        expect([diagram.title, diagram.axes, diagram.curves])
          .to eq([nil, [], []])
      end
    end

    context "with curve values" do
      radar_example(
        "parses positional values",
        <<~MERMAID,
          radar-beta
              axis A,B,C
              curve mycurve{1,2,3}
        MERMAID
        [1.0, 2.0, 3.0],
      ) do |diagram|
        curve = diagram.curves.first
        %w[A B C].map { |axis| curve.value_for(axis) }
      end

      it "ignores positional values beyond the last axis" do
        diagram = parser.parse("radar-beta\n  axis A,B\n  curve c{1,2,3}\n")

        expect(diagram.curves.first.values.size).to eq(2)
      end

      radar_example(
        "parses named values",
        <<~MERMAID,
          radar-beta
              axis A,B,C
              curve mycurve{ C: 3, A: 1, B: 2 }
        MERMAID
        [1.0, 2.0, 3.0],
      ) do |diagram|
        curve = diagram.curves.first
        %w[A B C].map { |axis| curve.value_for(axis) }
      end

      radar_example(
        "parses curve with label",
        <<~MERMAID,
          radar-beta
              axis A,B,C
              curve mycurve["My Curve"]{1,2,3}
        MERMAID
        ["mycurve", "My Curve"],
      ) do |diagram|
        curve = diagram.curves.first
        [curve.id, curve.label]
      end
    end

    context "with multiple curves" do
      it(
        "parses multiple curves",
        &radar_case(
          <<~MERMAID,
            radar-beta
                axis A, B, C
                curve mycurve["My Curve"]{1,2,3}
                curve mycurve2["My Curve 2"]{ C: 1, A: 2, B: 3 }
          MERMAID
          [2, "My Curve", "My Curve 2"],
        ) { |diagram| [diagram.curves.size, *diagram.curves.map(&:label)] }
      )
    end

    context "with options" do
      it(
        "parses ticks option",
        &radar_case(
          <<~MERMAID,
            radar-beta
                ticks 10
          MERMAID
          10,
        ) { |diagram| diagram.options[:ticks] }
      )

      radar_example(
        "parses showLegend option",
        <<~MERMAID,
          radar-beta
              showLegend false
        MERMAID
        false,
      ) { |diagram| diagram.options[:show_legend] }

      radar_example(
        "parses graticule option",
        <<~MERMAID,
          radar-beta
              graticule polygon
        MERMAID
        "polygon",
      ) { |diagram| diagram.options[:graticule] }

      radar_example(
        "parses min and max options",
        <<~MERMAID,
          radar-beta
              min 1
              max 10
        MERMAID
        [1.0, 10.0],
      ) { |diagram| diagram.options.values_at(:min, :max) }

      radar_example(
        "parses multiple options",
        <<~MERMAID,
          radar-beta
              ticks 10
              showLegend false
              graticule polygon
              min 1
              max 10
        MERMAID
        [10, false, "polygon", 1.0, 10.0],
      ) do |diagram|
        diagram.options.values_at(:ticks, :show_legend, :graticule, :min, :max)
      end
    end

    context "with comments" do
      it(
        "parses diagram with comments",
        &radar_case(
          <<~MERMAID,
            radar-beta
                %% This is a comment
                axis A,B,C
                %% This is another comment
                curve mycurve{1,2,3}
          MERMAID
          [3, 1],
        ) { |diagram| [diagram.axes.size, diagram.curves.size] }
      )
    end

    context "with the curve value-block constructs corpus case 003 uses" do
      it(
        "parses a curve with a space before the value block",
        &radar_case(
          <<~MERMAID,
            radar-beta
                axis A, B, C
                curve c1 {3, 2, 1}
          MERMAID
          [3.0, 1.0],
        ) do |diagram|
          curve = diagram.curves.first
          [curve.value_for("A"), curve.value_for("C")]
        end
      )

      radar_example(
        "parses named values without colons",
        <<~MERMAID,
          radar-beta
              axis A, B
              curve c1{A 1, B 2}
        MERMAID
        [1.0, 2.0],
      ) do |diagram|
        curve = diagram.curves.first
        [curve.value_for("A"), curve.value_for("B")]
      end

      radar_example(
        "parses a value block spanning multiple lines",
        <<~MERMAID,
          radar-beta
              axis A, B, C
              curve c1{
                  A: 1, B: 2,
                  C: 3
              }
        MERMAID
        [1.0, 2.0, 3.0],
      ) do |diagram|
        curve = diagram.curves.first
        %w[A B C].map { |axis| curve.value_for(axis) }
      end

      # A one-axis statement yields a Hash rather than an Array, and
      # Kernel#Array turns a Hash into its key/value pairs. Assignment used
      # to hide that because a later statement overwrote it; accumulating
      # keeps it, and the renderer then dies on a Symbol index. Every
      # existing example here used multi-axis statements, which is why the
      # regression got through.
      radar_example(
        "accumulates a single-axis statement into a later one",
        <<~MERMAID,
          radar-beta
              axis A
              axis B, C
              curve c1{1, 2, 3}
        MERMAID
        %w[A B C],
      ) { |diagram| diagram.axes.map(&:id) }

      radar_example(
        "accumulates axes across multiple axis statements",
        <<~MERMAID,
          radar-beta
              axis A, B, C
              axis D["Dee"], E["Ee"]
              curve c1{1, 2, 3, 4, 5}
        MERMAID
        [%w[A B C D E], ["A", "B", "C", "Dee", "Ee"],
         { "A" => 1.0, "B" => 2.0, "C" => 3.0, "D" => 4.0, "E" => 5.0 }],
      ) do |diagram|
        # Every position, so a mis-mapping across the two statements
        # cannot hide behind a single spot check.
        [diagram.axes.map(&:id), diagram.axes.map(&:label),
         diagram.curves.first.values]
      end

      corpus_source = File.read(
        File.expand_path(
          "../../mermaid/radar/003_rendering_radar_spec_radar_2.mmd",
          __dir__,
        ),
      )
      radar_example(
        "parses the full corpus case",
        corpus_source,
        [
          "My favorite ninjas",
          %w[Agility Speed Strength Stam Intel],
          %w[Ninja1 Ninja2 Ninja3],
          { "Agility" => 2.0, "Speed" => 2.0, "Strength" => 3.0,
            "Stam" => 5.0, "Intel" => 0.0 },
          { "Agility" => 2.0, "Speed" => 3.0, "Strength" => 4.0,
            "Stam" => 1.0, "Intel" => 5.0 },
          { "Agility" => 3.0, "Speed" => 2.0, "Strength" => 1.0,
            "Stam" => 5.0, "Intel" => 4.0 },
          { show_legend: true, ticks: 3, max: 8.0, min: 0.0,
            graticule: "polygon" },
        ],
      ) do |diagram|
        [
          diagram.title,
          diagram.axes.map(&:id),
          diagram.curves.map(&:id),
          *diagram.curves.map(&:values),
          diagram.options.slice(:show_legend, :ticks, :max, :min, :graticule),
        ]
      end
    end

    context "with complex example" do
      it(
        "parses a full radar diagram",
        &radar_case(
          <<~MERMAID,
            radar-beta
                title Radar diagram
                accTitle: Radar accTitle
                accDescr: Radar accDescription
                axis A["Axis A"], B["Axis B"] ,C["Axis C"]
                curve mycurve["My Curve"]{1,2,3}
                curve mycurve2["My Curve 2"]{ C: 1, A: 2, B: 3 }
                graticule polygon
          MERMAID
          ["Radar diagram", "Radar accTitle", "Radar accDescription", 3, 2,
           "polygon"],
        ) do |diagram|
          [diagram.title, diagram.acc_title, diagram.acc_descr,
           diagram.axes.size, diagram.curves.size,
           diagram.options[:graticule]]
        end
      )
    end
  end
end
