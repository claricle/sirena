# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram do
  describe Sirena::Diagram::FlowchartNode do
    subject(:node) { described_class.new(id: "start", label: "Start") }

    it "defaults to a rectangular shape" do
      expect(node.shape).to eq("rect")
    end

    it "accepts an id and label" do
      expect(node).to be_valid
    end

    it "rejects a missing id" do
      expect(described_class.new(label: "Start")).not_to be_valid
    end

    it "rejects an empty id" do
      expect(described_class.new(id: "", label: "Start")).not_to be_valid
    end

    it "rejects a missing label" do
      expect(described_class.new(id: "start")).not_to be_valid
    end
  end

  describe Sirena::Diagram::FlowchartEdge do
    subject(:edge) { described_class.new(source_id: "a", target_id: "b") }

    it "defaults to an arrow" do
      expect(edge.arrow_type).to eq("arrow")
    end

    it "accepts source and target ids" do
      expect(edge).to be_valid
    end

    {
      "a missing source" => { source_id: nil, target_id: "b" },
      "an empty source" => { source_id: "", target_id: "b" },
      "a missing target" => { source_id: "a", target_id: nil },
      "an empty target" => { source_id: "a", target_id: "" },
    }.each do |description, attributes|
      it "rejects #{description}" do
        expect(described_class.new(**attributes)).not_to be_valid
      end
    end
  end

  describe Sirena::Diagram::FlowchartSubgraph do
    it "uses an explicit title" do
      subgraph = described_class.new(id: "cluster", declared_title: "Cluster")

      expect(subgraph.title).to eq("Cluster")
    end

    it "falls back to its id when the title is missing" do
      expect(described_class.new(id: "cluster").title).to eq("cluster")
    end

    it "falls back to its id when the title is empty" do
      subgraph = described_class.new(id: "cluster", declared_title: "")

      expect(subgraph.title).to eq("cluster")
    end

    it "does not draw an empty subgraph" do
      expect(described_class.new(id: "cluster")).not_to be_drawable
    end

    it "draws a subgraph containing a node" do
      subgraph = described_class.new(id: "cluster", node_ids: ["a"])

      expect(subgraph).to be_drawable
    end

    it "draws a subgraph containing a child subgraph" do
      subgraph = described_class.new(id: "cluster", child_ids: ["child"])

      expect(subgraph).to be_drawable
    end

    it "accepts a non-empty id" do
      expect(described_class.new(id: "cluster")).to be_valid
    end

    it "rejects a missing id" do
      expect(described_class.new).not_to be_valid
    end

    it "rejects an empty id" do
      expect(described_class.new(id: "")).not_to be_valid
    end
  end
end
