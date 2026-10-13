# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart, :aggregate_failures do
  let(:parser) { described_class.new }

  context "when parsing simple flowchart with two nodes" do
    let(:source) { "graph TD\nA[Start]-->B[End]" }
    let(:diagram) { parser.parse(source) }

    it "retains diagram" do
      expect(diagram).to be_a(Sirena::Diagram::Flowchart)
    end

    it "retains diagram.direction" do
      expect(diagram.direction).to eq("TD")
    end

    it "retains diagram.nodes.length" do
      expect(diagram.nodes.length).to eq(2)
    end

    it "retains diagram.edges.length" do
      expect(diagram.edges.length).to eq(1)
    end
  end

  context "when parsing node with rectangle shape" do
    let(:source) { "graph TD\nA[Label Text]" }
    let(:diagram) { parser.parse(source) }

    it "retains node" do
      node = diagram.find_node("A")

      expect(node).not_to be_nil
    end

    it "retains node.label" do
      node = diagram.find_node("A")

      expect(node.label).to eq("Label Text")
    end

    it "retains node.shape" do
      node = diagram.find_node("A")

      expect(node.shape).to eq("rect")
    end
  end

  context "when parsing node with rounded shape" do
    let(:source) { "graph TD\nA(Rounded Label)" }
    let(:diagram) { parser.parse(source) }

    it "retains node" do
      node = diagram.find_node("A")

      expect(node).not_to be_nil
    end

    it "retains node.label" do
      node = diagram.find_node("A")

      expect(node.label).to eq("Rounded Label")
    end

    it "retains node.shape" do
      node = diagram.find_node("A")

      expect(node.shape).to eq("rounded")
    end
  end

  context "when parsing node with rhombus shape" do
    let(:source) { "graph TD\nA{Decision}" }
    let(:diagram) { parser.parse(source) }

    it "retains node" do
      node = diagram.find_node("A")

      expect(node).not_to be_nil
    end

    it "retains node.label" do
      node = diagram.find_node("A")

      expect(node.label).to eq("Decision")
    end

    it "retains node.shape" do
      node = diagram.find_node("A")

      expect(node.shape).to eq("rhombus")
    end
  end

  context "when parsing multiple edges in sequence" do
    let(:source) { "graph TD\nA-->B-->C" }
    let(:diagram) { parser.parse(source) }

    it "retains diagram.nodes.length" do
      expect(diagram.nodes.length).to eq(3)
    end

    it "retains diagram.edges.length" do
      expect(diagram.edges.length).to eq(2)
    end

    it "retains edge1.source_id" do
      edge1 = diagram.edges[0]

      expect(edge1.source_id).to eq("A")
    end

    it "retains edge1.target_id" do
      edge1 = diagram.edges[0]

      expect(edge1.target_id).to eq("B")
    end

    it "retains edge2.source_id" do
      edge2 = diagram.edges[1]

      expect(edge2.source_id).to eq("B")
    end

    it "retains edge2.target_id" do
      edge2 = diagram.edges[1]

      expect(edge2.target_id).to eq("C")
    end
  end

  it "parses flowchart with LR direction" do
    source = "graph LR\nA-->B"
    diagram = parser.parse(source)

    expect(diagram.direction).to eq("LR")
  end

  # No `@{}` anywhere on purpose. Re-mentioning a node is the widest
  # change on this branch and every spec that pinned it happened to carry
  # a metadata block, so restoring the old label default left them green.
  # mmdc draws B as a rhombus labelled `Choice`; it used to come out here
  # as a rectangle named `B`.
  it "keeps a label and shape given before the node was re-mentioned" do
    source = "graph TD\nA[Start] --> B{Choice}\nB -->|yes| C[End]"
    node = parser.parse(source).nodes.find { |n| n.id == "B" }

    expect([node.label, node.shape]).to eq(%w[Choice rhombus])
  end

  it "raises ParseError for invalid syntax" do
    source = "invalid syntax"
    expect { parser.parse(source) }.to raise_error(
      Sirena::Parser::ParseError,
    )
  end

  describe "#parse a class on a node already declared" do
    it "puts the class on the existing node" do
      diagram = parser.parse("graph TD\nA[x]\nA:::c\n")

      expect(diagram.nodes.map(&:classes)).to eq([":::c"])
    end
  end
end
