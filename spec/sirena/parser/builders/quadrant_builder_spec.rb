# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Quadrant do
  subject(:diagram) { described_class.new.apply(tree) }

  describe "hash-shaped trees" do
    context "with top-level fields and a statements list" do
      let(:tree) do
        {
          header: "quadrantChart",
          title: { string: " Top " },
          x_axis_left: "L", x_axis_right: "R",
          y_axis_bottom: "B", y_axis_top: "T",
          statements: [
            "noise",
            { title: "Inner" },
            { x_axis_left: "L2", x_axis_right: "R2" },
            { y_axis_bottom: "B2", y_axis_top: "T2" },
            { quadrant_number: "2", quadrant_label: "Q2" },
            { quadrant_number: "9", quadrant_label: "ignored" },
            { label: "P", coordinates: { x: "0.25", y: "0.75" },
              data_point: "\n" },
            { other: 1 },
          ]
        }
      end

      let(:point_triples) do
        diagram.points.map { |pt| [pt.label, pt.x, pt.y] }
      end

      it "applies top-level fields, then statements in order",
         :aggregate_failures do
        expect(diagram.title).to eq("Inner")
        expect([diagram.x_axis_left, diagram.x_axis_right]).to eq(%w[L2 R2])
        expect([diagram.y_axis_bottom, diagram.y_axis_top]).to eq(%w[B2 T2])
        expect(diagram.quadrant_2_label).to eq("Q2")
        expect(point_triples).to eq([["P", 0.25, 0.75]])
      end
    end

    context "with top-level fields only" do
      let(:tree) do
        { title: "Only", x_axis_left: "a", x_axis_right: "b",
          y_axis_bottom: "c", y_axis_top: "d" }
      end

      it "applies them without a statements list" do
        expect([diagram.title, diagram.x_axis_left,
                diagram.y_axis_top]).to eq(%w[Only a d])
      end
    end

    context "with no statements" do
      let(:tree) { { header: "quadrantChart", title: "Just" } }

      it "keeps the top-level title" do
        expect(diagram.title).to eq("Just")
      end
    end

    context "with an empty title" do
      let(:tree) { { title: "   " } }

      it "leaves the title unset" do
        expect(diagram.title).to be_nil
      end
    end

    context "with a nil title value" do
      let(:tree) { { title: nil } }

      it "leaves the title unset" do
        expect(diagram.title).to be_nil
      end
    end
  end

  describe "array-shaped trees" do
    context "with non-hash entries and quadrant labels 1 to 4" do
      let(:tree) do
        [
          "noise",
          { quadrant_number: "1", quadrant_label: "A" },
          { quadrant_number: "3", quadrant_label: "C" },
          { quadrant_number: "4", quadrant_label: "D" },
          { quadrant_number: "5", quadrant_label: "ignored" },
        ]
      end

      it "assigns the matching label slots", :aggregate_failures do
        expect([diagram.quadrant_1_label, diagram.quadrant_3_label,
                diagram.quadrant_4_label]).to eq(%w[A C D])
        expect(diagram.quadrant_2_label).to be_nil
      end
    end
  end

  describe "data points" do
    let(:tree) { points.map { |pt| pt.merge(data_point: "\n") } }

    context "with blank label or missing coordinates" do
      let(:points) do
        [{ label: "", coordinates: { x: "1", y: "1" } }, { label: "NoCoords" }]
      end

      it "skips them" do
        expect(diagram.points).to be_empty
      end
    end

    context "with array styling including non-hash items" do
      let(:points) do
        [{ label: "S", coordinates: { x: "0.5", y: "0.5" },
           styling: ["junk", { radius: "10" }, { color: { string: "#f00" } },
                     { stroke_color: "#0f0" }, { stroke_width: "3" }] }]
      end

      it "reads each style attribute" do
        pt = diagram.points.first
        expect([pt.radius, pt.color, pt.stroke_color,
                pt.stroke_width]).to eq([10.0, "#f00", "#0f0", 3.0])
      end
    end

    context "with hash styling" do
      let(:points) do
        [{ label: "S", coordinates: { x: { v: "0.5" }, y: "0.5" },
           styling: { radius: { r: "7" } } }]
      end

      it "wraps it and unwraps single-key hashes in numbers" do
        pt = diagram.points.first
        expect([pt.x, pt.radius]).to eq([0.5, 7.0])
      end
    end

    context "with styling of an unsupported type" do
      let(:points) do
        [{ label: "S", coordinates: { x: "0.5", y: "0.5" },
           styling: "radius: 3" }]
      end

      it "ignores the styling" do
        expect(diagram.points.first.radius).to be_nil
      end
    end

    context "with a label that is a non-string value" do
      let(:points) { [{ label: 42, coordinates: { x: "0.1", y: "0.2" } }] }

      it "stringifies it" do
        expect(diagram.points.first.label).to eq("42")
      end
    end
  end
end
