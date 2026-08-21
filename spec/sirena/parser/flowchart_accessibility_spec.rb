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

  # mermaid strips comments before reading the statement, so a comment on
  # its OWN line is skipped while one on the delimiter's line is text.
  describe "a standalone comment line" do
    it "is skipped between the delimiter and its text" do
      source = "graph TD\naccTitle:\n%% comment\nActualTitle\nA --- B\n"

      expect(node_ids(source)).to eq(%w[A B])
      expect(acc_text(source)).to eq("ActualTitle")
    end

    it "does not close a block with a brace inside it" do
      # mmdc swallows every line after the open brace here.
      source = "graph TD\naccDescr {\ntext\n%% }\nC --- D\n"

      expect(node_ids(source)).to eq([])
    end

    it "hides its brace at the end of the source" do
      # No trailing newline. The comment used to need one, so this line
      # was read character by character, the `}` closed the block and
      # C --- D came back as a second edge. mmdc draws only A and B.
      source = "graph TD\nA --- B\naccDescr {\ntext\n%% } C --- D"

      expect(node_ids(source)).to eq(%w[A B])
    end

    # mermaid's `\s` is wider than a space and a tab, so mmdc strips a
    # `%%` line that a no-break space or a form feed pushed across.
    {
      "spaces" => "   ",
      "a tab" => "\t",
      "a no-break space" => "\u00A0",
      "a form feed" => "\f"
    }.each do |label, indent|
      it "is still a comment after #{label}" do
        source = "graph TD\nA --- B\naccDescr {\ntext\n#{indent}%% } C --- D\n"

        expect(node_ids(source)).to eq(%w[A B])
      end
    end

    it "is still a comment after a lone carriage return" do
      source = "graph TD\nA --- B\naccDescr {\ntext\n\r%% } C --- D\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "is still a comment after a zero-width no-break space" do
      source = "graph TD\nA --- B\naccDescr {\ntext\n\uFEFF%% } C --- D\n"

      expect(node_ids(source)).to eq(%w[A B])
    end

    it "is not a comment after a next-line character" do
      # U+0085 is not whitespace to mmdc, so the `%%` never reaches the
      # line start, the line stays description text and the `}` closes
      # the block. mmdc draws C and D here.
      source = "graph TD\nA --- B\naccDescr {\ntext\n\u0085%% } C --- D\n"

      expect(node_ids(source)).to eq(%w[A B C D])
    end

    it "does not start in the middle of a line" do
      # mermaid strips from the line start only. mmdc closes the block on
      # this `}` and draws C and D.
      source = "graph TD\nA --- B\naccDescr {\ntext %% } C --- D\n"

      expect(node_ids(source)).to eq(%w[A B C D])
    end

    it "still keeps a same-line comment as text" do
      source = "graph TD\naccTitle: %% comment\nA --- B\nC --- D\n"

      expect(acc_text(source)).to eq("%% comment")
      expect(node_ids(source)).to eq(%w[A B C D])
    end
  end

  # mermaid puts `\s*` between the keyword and its delimiter, and `\s` is
  # every one of these. A narrow gap threw the whole diagram away on
  # sources mmdc draws. Each entry was measured against mmdc 11.12.0.
  describe "the spaces mermaid counts before the delimiter" do
    {
      # A lone carriage return is a space, not a line end.
      "a carriage return" => "\r",
      "a tab" => "\t",
      "a vertical tab" => "\v",
      "a form feed" => "\f",
      "a space" => " ",
      "a no-break space" => "\u00A0",
      "an ogham space mark" => "\u1680",
      "an en quad" => "\u2000",
      "a hair space" => "\u200A",
      "a line separator" => "\u2028",
      "a paragraph separator" => "\u2029",
      "a narrow no-break space" => "\u202F",
      "a medium mathematical space" => "\u205F",
      "an ideographic space" => "\u3000",
      "a zero-width no-break space" => "\uFEFF"
    }.each do |label, gap|
      it "still finds the colon after #{label}" do
        source = "graph TD\nA --- B\naccTitle#{gap}: Hi\nC --- D\n"

        expect(node_ids(source)).to eq(%w[A B C D])
      end
    end

    it "takes the same gap before a block brace" do
      source = "graph TD\nA --- B\naccDescr\u00A0{Hi}\nC --- D\n"

      expect(node_ids(source)).to eq(%w[A B C D])
    end

    it "still finds the brace on the next line" do
      source = "graph TD\nA --- B\naccDescr\n\u00A0{Hi}\nC --- D\n"

      expect(node_ids(source)).to eq(%w[A B C D])
    end

    it "keeps the text once the gap has eaten the space" do
      source = "graph TD\nA --- B\naccTitle\u00A0: Hi\nC --- D\n"

      expect(acc_text(source)).to eq("Hi")
    end

    it "does not count a next-line character" do
      # mmdc rejects this source outright, so taking U+0085 for a space
      # invented a diagram mermaid will not draw.
      source = "graph TD\nA --- B\naccTitle\u0085: Hi\nC --- D\n"

      expect { node_ids(source) }.to raise_error(Sirena::Parser::ParseError)
    end

    it "crosses the line end after the colon and takes the next line" do
      # The gap eats the no-break space, then the newline, so mmdc's
      # title here is `C --- D` and that edge is gone. A narrow gap
      # stopped at the space and left the edge behind.
      source = "graph TD\nA --- B\naccTitle:\u00A0\nC --- D\n"

      expect(node_ids(source)).to eq(%w[A B])
      expect(acc_text(source)).to eq("C --- D")
    end
  end

  it "takes a spaced semicolon after a closing block" do
    source = "graph TD\nA --- B\naccDescr {Desc} ; C --- D\n"

    expect(node_ids(source)).to eq(%w[A B C D])
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
