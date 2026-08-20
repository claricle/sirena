# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  def node_ids(source)
    described_class.new.parse(source).nodes.map(&:id).sort
  end

  describe "accessibility statements" do
    # mermaid puts these in the SVG's aria attributes. They are ordinary
    # statements in a diagram and had no rule at all.
    it "takes accTitle" do
      source = "graph TD\naccTitle: Big decisions\nA-->B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "takes accDescr" do
      source = "graph TD\naccDescr: Some text\nA-->B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "takes the braced accDescr block" do
      source = "graph TD\naccDescr {\n  multi line\n}\nA-->B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "takes the text from the next line" do
      # mermaid separates the keyword from its delimiter with \s*, which
      # crosses newlines. A horizontal-only rule made a node called Title.
      source = "graph TD\naccTitle:\nTitle\nA-->B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "takes a brace on the next line" do
      source = "graph TD\naccDescr\n{\nDesc\n}\nA-->B\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "ends the block at its closing brace" do
      # Requiring a line end after `}` rejected this, which mermaid
      # renders; the statement rule handles what follows.
      expect(node_ids("graph TD\naccDescr {Desc}A-->B\n")).to eq(%w[A B])
    end
  end

  describe "nodes whose names contain the keyword" do
    # `account` shares only a prefix. These share the WHOLE keyword, which
    # is what the boundary actually has to get right.
    %w[accTitleNode accDescrNode account].each do |id|
      it "leaves #{id} alone" do
        expect(node_ids("graph TD\n#{id}-->B\n")).to eq(["B", id].sort)
      end
    end
  end

  describe "a diagram with no accessibility statement" do
    it "keeps its edge, not just its nodes" do
      # Checking node ids alone let the edge disappear unnoticed.
      diagram = described_class.new.parse("graph TD\nA-->B\nA-->C\n")

      expect(diagram.nodes.map(&:id).sort).to eq(%w[A B C])
      expect(diagram.edges.map { |e| [e.source_id, e.target_id] })
        .to eq([%w[A B], %w[A C]])
    end
  end
end
