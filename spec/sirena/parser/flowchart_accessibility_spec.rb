# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  def node_ids(source)
    described_class.new.parse(source).nodes.map(&:id).sort
  end

  # The text is parsed and discarded — nothing carries it onto the model
  # yet — so the grammar's own capture is where it can be asserted.
  def acc_text(source)
    tree = Sirena::Parser::Grammars::Flowchart.new.parse(source)
    Array(tree).flat_map { |node| node.is_a?(Hash) ? [node] : [] }
      .find { |node| node.key?(:acc_text) }&.fetch(:acc_text)
      &.to_s
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

  # The gap between the keyword and its delimiter crosses newlines but not
  # comments. Skipping comments too made the statement swallow whatever
  # followed the comment.
  describe "a comment after the delimiter" do
    it "is title text, not a comment" do
      # The text is parsed and discarded, so the tree is where it shows.
      # The surviving `C-->D` is the other half of the proof: skipping the
      # comment made the next statement the title instead.
      source = "graph TD\naccTitle: %% comment\nA-->B\nC-->D\n"

      expect(node_ids(source)).to eq(%w[A B C D])
      expect(acc_text(source)).to eq("%% comment")
    end

    it "leaves both edges alone after accDescr" do
      source = "graph TD\naccDescr: %% description\nA-->B\nC-->D\n"
      diagram = described_class.new.parse(source)

      expect(diagram.edges.map { |e| [e.source_id, e.target_id] })
        .to eq([%w[A B], %w[C D]])
    end

    it "still takes the text from the next line" do
      # The gap does cross a newline — that is what it is for.
      source = "graph TD\naccTitle:\nThe title\nA-->B\n"

      expect(acc_text(source)).to eq("The title")
      expect(node_ids(source)).to eq(%w[A B])
    end
  end

  # mmdc renders all of these; refusing them lost a diagram it draws.
  describe "an incomplete accessibility statement" do
    {
      "an empty title" => "graph TD\nA-->B\naccTitle:\n",
      "an empty description" => "graph TD\nA-->B\naccDescr:\n",
      "an unterminated block" => "graph TD\nA-->B\naccDescr {Unterminated\n"
    }.each do |label, source|
      it "keeps the diagram for #{label}" do
        expect(node_ids(source)).to eq(%w[A B])
      end
    end

    it "lets an unterminated block swallow the rest, as mermaid does" do
      # mmdc draws only A and B here: everything after the open brace is
      # description text.
      source = "graph TD\nA-->B\naccDescr {Unterm\nC-->D\n"

      expect(node_ids(source)).to eq(%w[A B])
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
