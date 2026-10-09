# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::C4 do
  subject(:diagram) { described_class.new.apply(tree) }

  describe "header level" do
    {
      "C4Context" => "Context",
      "C4Container" => "Container",
      "C4Component" => "Component",
      "C4Dynamic" => "Dynamic",
      "C4Deployment" => "Deployment",
      "C4 diagram" => "Context",
      "C4Unknown" => "Context",
    }.each do |header, level|
      it "maps #{header} to #{level}" do
        built = described_class.new.apply([{ header: header }])
        expect(built.level).to eq(level)
      end
    end

    it "reads the level from a lone header hash" do
      built = described_class.new.apply({ header: "C4Dynamic" })
      expect(built.level).to eq("Dynamic")
    end

    it "leaves the default level when there is no header" do
      expect(described_class.new.apply([{ title: "T" }]).title).to eq("T")
    end
  end

  describe "statement dispatch" do
    context "with a single non-header hash" do
      let(:tree) { { title: { string: " Solo " } } }

      it "processes it directly and unwraps string hashes" do
        expect(diagram.title).to eq("Solo")
      end
    end

    context "with non-hash noise, a bare header and an unknown statement" do
      let(:tree) { ["noise", { header: "C4Context" }, { other: 1 }] }

      it "ignores all of it" do
        expect([diagram.elements, diagram.boundaries,
                diagram.relationships]).to all(be_empty)
      end
    end
  end

  describe "layout config" do
    context "with an array of params" do
      let(:tree) do
        [{ config_params: [{ key: "a", value: "1" }, { key: "b" },
                           { value: "3" },
                           { key: "c", value: { string: "4" } }] }]
      end

      it "joins only the complete key=value pairs" do
        expect(diagram.layout_config).to eq("a=1, c=4")
      end
    end

    context "with a single hash param" do
      let(:tree) { [{ config_params: { key: "k", value: "v" } }] }

      it "renders one pair" do
        expect(diagram.layout_config).to eq("k=v")
      end
    end
  end

  describe "text extraction" do
    let(:tree) do
      [{ element_type: "System", id: { var: " ${v} " },
         label: { other: " first " }, description: 42 }]
    end

    it "uses var, the first hash value, or to_s" do
      el = diagram.elements.first
      expect([el.id, el.label, el.description]).to eq(["${v}", "first", "42"])
    end
  end

  describe "elements" do
    context "with a macro-variable element type and every attribute" do
      let(:tree) do
        [{ element_type: { variable: { var: "${macro}" } }, id: "a",
           label: "A", description: "d", technology: "t", sprite: "s",
           link: "l", tags: "g" }]
      end

      it "copies every attribute and is not external" do
        el = diagram.elements.first
        expect([el.element_type, el.id, el.label, el.description,
                el.technology, el.sprite, el.link, el.tags, el.external])
          .to eq(["${macro}", "a", "A", "d", "t", "s", "l", "g", false])
      end
    end

    context "with an external type and no attributes" do
      let(:tree) { [{ element_type: "Person_Ext" }] }

      it "is external with a nil id" do
        el = diagram.elements.first
        expect([el.external, el.id, el.label]).to eq([true, nil, nil])
      end
    end

    context "with attributes scattered across following hashes" do
      let(:tree) do
        [{ element_type: "System", id: "a" }, { label: "A" },
         { description: "d" }, { element_type: "Person", id: "b" }]
      end

      it "merges them into the element they follow, stopping at the next" do
        expect(diagram.elements.map { |e| [e.id, e.label, e.description] })
          .to eq([["a", "A", "d"], ["b", nil, nil]])
      end
    end
  end

  describe "relationships" do
    context "with every part" do
      let(:tree) do
        [{ rel_type: "Rel", from: "a", to: "b", label: "uses",
           technology: "http" }]
      end

      it "copies each part" do
        rel = diagram.relationships.first
        expect([rel.rel_type, rel.from_id, rel.to_id, rel.label,
                rel.technology])
          .to eq(["Rel", "a", "b", "uses", "http"])
      end
    end

    context "with only a type" do
      let(:tree) { [{ rel_type: "BiRel" }] }

      it "leaves the optional parts nil" do
        rel = diagram.relationships.first
        expect([rel.from_id, rel.to_id, rel.label,
                rel.technology]).to all(be_nil)
      end
    end
  end

  describe "boundaries" do
    context "with a variable boundary type, no id or label" do
      let(:tree) { [{ boundary_type: { variable: { var: "${b}" } } }] }

      it "records the variable and leaves parts nil" do
        b = diagram.boundaries.first
        expect([b.boundary_type, b.id, b.label,
                b.parent_id]).to eq(["${b}", nil, nil, nil])
      end
    end

    context "with link, tags, type and a body mixing boundaries and elements" do
      let(:inner_item) do
        { item: { boundary_type: "Enterprise_Boundary", id: "inner",
                  label: "I", type: "ty", link: "il", tags: "ig",
                  body: [{ item: { element_type: "Person", id: "p1" } },
                         { skip: true },
                         { item: { boundary_type: "Boundary" } }] } }
      end
      let(:tree) do
        [{ boundary_type: "Boundary", id: "outer", label: "O", type: "t",
           link: "l", tags: "g",
           body: [
             { item: { element_type: "System", id: "s1" } },
             inner_item,
             { item: { other: 1 } },
             { not_an_item: 1 },
           ] }]
      end

      let(:outer) { diagram.boundaries.first }
      let(:inner) { diagram.boundaries[1] }
      let(:element_boundaries) do
        diagram.elements.to_h { |e| [e.id, e.boundary_id] }
      end

      it "records outer attributes and members", :aggregate_failures do
        expect([outer.link, outer.tags, outer.type_param]).to eq(%w[l g t])
        expect(outer.boundary_ids).to eq(["inner"])
        expect(outer.element_ids).to eq(["s1"])
      end

      it "records inner attributes and members", :aggregate_failures do
        expect([inner.parent_id, inner.link, inner.tags, inner.type_param])
          .to eq(["outer", "il", "ig", "ty"])
        expect(inner.element_ids).to eq(["p1"])
      end

      it "assigns contained elements to their boundary" do
        expect(element_boundaries).to eq("s1" => "outer", "p1" => "inner")
      end
    end

    context "with a single-hash body" do
      let(:tree) do
        [{ boundary_type: "Boundary", id: "o",
           body: { item: { element_type: "System", id: "x" } } }]
      end

      it "treats it as a one-item body" do
        expect(diagram.boundaries.first.element_ids).to eq(["x"])
      end
    end

    context "with a nested boundary variable type" do
      let(:tree) do
        [{ boundary_type: "Boundary", id: "o",
           body: [{ item: { boundary_type: { variable: { var: "${n}" } },
                            id: "n1" } }] }]
      end

      it "records the variable type on the nested boundary" do
        types = diagram.boundaries.map(&:boundary_type)
        expect(types).to eq(["Boundary", "${n}"])
      end
    end
  end
end
