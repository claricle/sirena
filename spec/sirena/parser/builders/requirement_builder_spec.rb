# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Requirement do
  let(:diagram) { described_class.new.apply(tree) }

  describe "#apply" do
    context "with a single hash instead of an array" do
      let(:tree) { { req_type: "requirement", req_name: "solo" } }

      it "wraps it and builds a property-less requirement",
         :aggregate_failures do
        expect(diagram.requirements.map(&:name)).to eq(["solo"])
        expect(diagram.requirements.first.id).to be_nil
      end
    end

    context "with non-hash entries and unknown statements" do
      let(:tree) do
        ["junk", { header: "requirementDiagram" }, { unknown: "x" },
         { acc_descr: [] }]
      end

      it "skips the noise and normalises an empty accDescr to an empty string",
         :aggregate_failures do
        expect(diagram.requirements).to be_empty
        expect(diagram.acc_description).to eq("")
      end
    end

    context "with single (non-array) property hashes" do
      let(:tree) do
        [
          { req_type: "requirement", req_name: "r",
            req_properties: { key: { prop_key: "risk" }, value: " high " } },
          { elem_keyword: "element", elem_name: "e",
            elem_properties: { key: { prop_key: "docref" }, value: " a.md " } },
        ]
      end

      it "treats each as a one-element list and strips values",
         :aggregate_failures do
        expect(diagram.requirements.first.risk).to eq("high")
        expect(diagram.elements.first.docref).to eq("a.md")
      end
    end

    context "with property entries lacking a key, a value, or a hash shape" do
      let(:tree) do
        [
          { req_type: "requirement", req_name: "r",
            req_properties: ["stray", { value: "v" },
                             { key: { prop_key: "id" } },
                             { key: { prop_key: "text" }, value: "t" }] },
          { elem_keyword: "element", elem_name: "e",
            elem_properties: ["stray", { value: "v" },
                              { key: { prop_key: "type" } },
                              { key: { prop_key: "bogus" }, value: "z" }] },
        ]
      end

      it "ignores the unusable entries and keeps the usable one",
         :aggregate_failures do
        req = diagram.requirements.first
        expect([req.id, req.text]).to eq([nil, "t"])
        expect(diagram.elements.first.type).to be_nil
      end
    end

    context "with class shorthand strings" do
      let(:tree) do
        [
          { req_type: "requirement", req_name: "r", req_classes: "a, b" },
          { elem_keyword: "element", elem_name: "e", elem_classes: %w[x y] },
        ]
      end

      it "splits a comma string and accepts an array", :aggregate_failures do
        expect(diagram.requirements.first.classes).to eq(%w[a b])
        expect(diagram.elements.first.classes).to eq(%w[x y])
      end
    end

    context "with a relationship that has no type" do
      let(:tree) { [{ rel_source: "a", rel_target: "b" }] }

      it "keeps source and target and leaves the type unset" do
        rel = diagram.relationships.first
        expect([rel.source, rel.target, rel.type]).to eq(["a", "b", nil])
      end
    end

    context "with style statements" do
      let(:tree) do
        [
          { style_keyword: "style", style_targets: "a",
            style_props:
              "fill:#111, stroke:#222, stroke-width:3px, ,color:red" },
          { style_keyword: "style" },
          { style_keyword: "style", style_targets: %w[b c],
            style_props: ["fill:#333"] },
        ]
      end

      it "assigns known properties and keeps the rest", :aggregate_failures do
        style = diagram.styles.first
        expect([style.fill, style.stroke,
                style.stroke_width]).to eq(["#111", "#222", "3px"])
        expect(style.properties).to eq(["color:red"])
        expect(style.target_ids).to eq(["a"])
      end

      it "tolerates an empty style and handles list forms",
         :aggregate_failures do
        expect(diagram.styles[1].target_ids).to be_empty
        expect(diagram.styles[2].target_ids).to eq(%w[b c])
        expect(diagram.styles[2].fill).to eq("#333")
      end
    end

    context "with classDef statements" do
      let(:tree) do
        [
          { classdef_keyword: "classDef", class_name: "k",
            class_props:
              "fill:#111, stroke:#222, stroke-width:3px, ,color:red" },
          { classdef_keyword: "classDef", class_name: "bare" },
          { classdef_keyword: "classDef", class_name: "listy",
            class_props: ["stroke:#999"] },
        ]
      end

      it "assigns known properties and keeps the rest", :aggregate_failures do
        klass = diagram.classes.first
        expect([klass.fill, klass.stroke,
                klass.stroke_width]).to eq(["#111", "#222", "3px"])
        expect(klass.properties).to eq(["color:red"])
      end

      it "tolerates a classDef without properties and accepts list properties",
         :aggregate_failures do
        expect(diagram.classes[1].properties).to be_empty
        expect(diagram.classes[2].stroke).to eq("#999")
      end
    end

    context "with class assignments" do
      let(:tree) do
        [
          { class_keyword: "class", class_targets: "a", class_names: "k" },
          { class_keyword: "class", class_targets: %w[b c],
            class_names: %w[k m] },
          { class_keyword: "class" },
        ]
      end

      it "wraps scalars and keeps arrays", :aggregate_failures do
        expect(diagram.class_assignments[0].target_ids).to eq(["a"])
        expect(diagram.class_assignments[0].class_names).to eq(["k"])
        expect(diagram.class_assignments[1].target_ids).to eq(%w[b c])
        expect(diagram.class_assignments[2].class_names).to be_empty
      end
    end
  end

  describe "#extract_class_names" do
    it "splits a string on commas and strips" do
      expect(described_class.new.extract_class_names(" a , b ")).to eq(%w[a b])
    end

    it "drops the ::: prefix of the Parslet::Slice the grammar produces" do
      slice = Parslet::Slice.new(Parslet::Position.new(":::a, b", 0), ":::a, b")
      expect(described_class.new.extract_class_names(slice)).to eq(%w[a b])
    end

    it "returns nothing for other types" do
      expect(described_class.new.extract_class_names(nil)).to eq([])
    end
  end
end
