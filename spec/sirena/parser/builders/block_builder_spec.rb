# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Block do
  subject(:diagram) { described_class.new.apply(tree) }

  describe "tree normalisation" do
    context "with a single hash instead of an array" do
      let(:tree) { { block_id: "solo" } }

      it "wraps it" do
        expect(diagram.blocks.map(&:id)).to eq(["solo"])
      end
    end

    context "with non-hash entries and a columns statement" do
      let(:tree) do
        ["junk", { columns_keyword: "columns" },
         { columns_keyword: "columns", columns_value: "4" }, { block_id: "a" }]
      end

      it "reads the first complete columns value and skips junk",
         :aggregate_failures do
        expect(diagram.columns).to eq(4)
        expect(diagram.blocks.map(&:id)).to eq(["a"])
      end
    end
  end

  describe "block kinds" do
    context "with space, arrow, compound and plain blocks in a compound" do
      let(:tree) do
        [
          { block_id: "top" },
          { space_keyword: "space" },
          { arrow_id: "arr" },
          { arrow_id: "arr2", arrow_label: "go", arrow_direction: "right" },
          { compound_keyword: "block", compound_id: "grp",
            compound_statements: [
              { space_keyword: "space" },
              { arrow_id: "inner_arrow" },
              { compound_keyword: "block",
                compound_statements: { block_id: "deep" } },
              { block_id: "c" },
            ] },
          { compound_keyword: "block" },
        ]
      end

      it "builds top-level blocks with positional anonymous ids" do
        expect(diagram.blocks.map(&:id)).to eq(%w[top space-1 arr arr2 grp
                                                  compound-5])
      end

      it "sets arrow label and direction only when given" do
        arrows = diagram.blocks.select(&:arrow?)
        pairs = arrows.map { |a| [a.label, a.direction] }
        expect(pairs).to eq([[nil, nil], %w[go right]])
      end

      it "nests children under the compound with parent-prefixed anonymous ids",
         :aggregate_failures do
        grp = diagram.blocks.find { |b| b.id == "grp" }
        expect(grp).to be_compound
        expect(grp.children.map(&:id)).to eq(%w[grp-space-0 inner_arrow
                                                grp-compound-2 c])
        expect(grp.children[2].children.map(&:id)).to eq(["deep"])
      end

      it "gives a compound without statements no children" do
        expect(diagram.blocks.last.children).to be_empty
      end
    end
  end

  describe "block width and shape" do
    let(:tree) do
      [
        { block_id: "w1", block_width: { width: "3" } },
        { block_id: "w2", block_width: ":2" },
        { block_id: "s1",
          block_shape: { open: "((", close: "))", label: "\"Circle\"" } },
        { block_id: "s2",
          block_shape: { open: "<", close: ">", label: "'odd'" } },
        { block_id: "s3", block_shape: { shape_type: "circle", label: "Pre" } },
        { block_id: "s4", block_shape: { shape_type: "circle" } },
        { block_id: "s5", block_shape: { unknown: 1 } },
        { block_id: "s6", block_shape: "raw" },
      ]
    end

    it "reads hash and raw widths" do
      expect(diagram.blocks.first(2).map(&:width)).to eq([3, 2])
    end

    it "maps raw delimiters to shapes and strips quotes from labels" do
      pairs = diagram.blocks[2..3].map { |b| [b.shape, b.label] }
      expect(pairs).to eq([%w[circle Circle], %w[rect odd]])
    end

    it "accepts already-transformed shapes, defaulting the label to the id" do
      pairs = diagram.blocks[4..5].map { |b| [b.shape, b.label] }
      expect(pairs).to eq([%w[circle Pre], %w[circle s4]])
    end

    it "leaves shape and label alone for unrecognised shape data" do
      pairs = diagram.blocks[6..7].map { |b| [b.shape, b.label] }
      expect(pairs).to eq([["rect", nil], ["rect", nil]])
    end

    it "labels shapeless blocks with their id" do
      plain = described_class.new.apply([{ block_id: "plain" }])
      expect(plain.blocks.first.label).to eq("plain")
    end
  end

  describe "connections" do
    let(:tree) do
      [
        { from: "a", to: "b", arrow: { arrow_type: "-->" } },
        { from: "b", to: "c", arrow: { line_type: "---" } },
        { from: "c", to: "d", arrow: { arrow_type: "~~>" } },
        { from: "d", to: "e", arrow: {} },
        { from: "e", to: "f" },
      ]
    end

    it "maps known arrows, defaulting unknown or missing ones to arrow" do
      types = diagram.connections.map(&:connection_type)
      expect(types).to eq(%w[arrow line arrow arrow arrow])
    end
  end

  describe "styles" do
    let(:tree) do
      [
        { style_keyword: "style", style_target: "a",
          style_props: ["fill:#f00", " stroke:#0f0 ", "stroke-width:4px",
                        "color:#fff"] },
        { style_keyword: "style", style_target: "b", style_props: "fill:#111" },
        { style_keyword: "style", style_target: "c" },
      ]
    end

    it "assigns known properties and keeps the rest" do
      style = diagram.styles.first
      expect([style.block_id, style.fill, style.stroke, style.stroke_width,
              style.properties])
        .to eq(["a", "#f00", "#0f0", "4px", ["color:#fff"]])
    end

    it "wraps a single property and tolerates none", :aggregate_failures do
      expect(diagram.styles[1].fill).to eq("#111")
      expect(diagram.styles[2].properties).to be_empty
    end
  end
end
