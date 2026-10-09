# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::Architecture do
  subject(:diagram) { described_class.new.apply(tree) }

  context "with a lone hash statement" do
    let(:tree) { { title: { string: "Solo" } } }

    it "processes it directly" do
      expect(diagram.title).to eq("Solo")
    end
  end

  context "with noise, header, accessibility fields and unknown statements" do
    let(:tree) do
      ["noise", { header: "architecture-beta" }, { acc_title: "AT" },
       { acc_descr: [] }, { stmt_type: "other" }, { unrelated: 1 }]
    end

    it "keeps the accessibility text and ignores the rest",
       :aggregate_failures do
      expect(diagram.acc_title).to eq("AT")
      expect(diagram.acc_descr).to eq("")
      expect([diagram.groups, diagram.services, diagram.junctions,
              diagram.edges]).to all(be_empty)
    end
  end

  context "with fully populated statements" do
    let(:tree) do
      [
        { stmt_type: "group", id: "g", label: "G", icon: "cloud",
          parent: "root" },
        { stmt_type: "service", id: "s", label: "S", icon: "db", group: "g" },
        { stmt_type: "junction", id: "j", group: "g" },
        { from: "s", to: "j", from_pos: "R", to_pos: "L", label: "link" },
      ]
    end

    let(:group) { diagram.groups.first }
    let(:service) { diagram.services.first }
    let(:junction) { diagram.junctions.first }
    let(:edge) { diagram.edges.first }

    it "fills group and service attributes", :aggregate_failures do
      expect([group.id, group.label, group.icon,
              group.parent_id]).to eq(%w[g G cloud root])
      expect([service.id, service.label, service.icon,
              service.group_id]).to eq(%w[s S db g])
    end

    it "fills junction and edge attributes", :aggregate_failures do
      expect([junction.id, junction.group_id]).to eq(%w[j g])
      expect([edge.from_id, edge.to_id, edge.from_position, edge.to_position,
              edge.label]).to eq(%w[s j R L link])
    end
  end

  context "with minimal statements and empty parent/group values" do
    let(:tree) do
      [
        { stmt_type: "group", parent: "" },
        { stmt_type: "service", group: "" },
        { stmt_type: "junction", group: "" },
        { from: "a", to: "b" },
      ]
    end

    it "leaves optional attributes unset", :aggregate_failures do
      expect(diagram.groups.first.parent_id).to be_nil
      expect(diagram.services.first.group_id).to be_nil
      expect(diagram.junctions.first.group_id).to be_nil
      edge = diagram.edges.first
      expect([edge.from_position, edge.to_position, edge.label]).to all(be_nil)
    end
  end

  context "with string-wrapped hashes and other hash shapes" do
    let(:tree) do
      [{ stmt_type: { string: "service" }, id: { string: "a" },
         label: { other: "first" } }]
    end

    it "unwraps :string and falls back to the first value" do
      service = diagram.services.first
      expect([service.id, service.label]).to eq(%w[a first])
    end
  end
end
