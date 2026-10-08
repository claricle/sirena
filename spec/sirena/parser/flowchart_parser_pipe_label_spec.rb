# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Flowchart do
  include FlowchartParserHelpers

  describe "a label written between pipes" do
    {
      "A -->|t| B" => "arrow",
      "A ---|t| B" => "line",
      "A --x|t| B" => "cross",
      "A --o|t| B" => "circle",
      "A <-->|t| B" => "arrow_both",
      "A ==>|t| B" => "thick_arrow",
      "A ===|t| B" => "thick_line",
      "A -.->|t| B" => "dotted_arrow",
      "A -.-|t| B" => "dotted_line",
      "A ~~~|t| B" => "invisible",
    }.each do |source, arrow_type|
      it "reads #{source.inspect} as one #{arrow_type} edge labelled t" do
        expect(edge_tuples(source)).to eq([["A", "B", "t", arrow_type]])
      end
    end

    {
      "A -->|yes| B" => "yes",
      "A -->|x|B" => "x",
      "A -->| yes | B" => "yes",
      "A -->|\t\u00A0yes\u3000\uFEFF| B" => "yes",
      "A -->|a   b| B" => "a   b",
      "A -->|a-b/c| B" => "a-b/c",
      "A -->|\"a b\"| B" => "a b",
      "A -->|\"  a  \"| B" => "a",
      "A -->|\"a\"b| B" => "ab",
      "A -->|\"a (b) [c]\"| B" => "a (b) [c]",
      "A -->|\n  a\n  b\n| B" => "a\n  b",
    }.each do |source, label|
      it "reads the text of #{source.inspect} as #{label.inspect}" do
        expect(edge_tuples(source).map { |e| e[2] }).to eq([label])
      end
    end

    it "drops a comment line inside the text, as mermaid lexes" do
      source = "A -->|a\n%% note\nb| B"

      expect(edge_tuples(source).first[2]).to eq("a\nb")
    end

    {
      "A -->|  | B" => "only space",
      "A -->|\t\u00A0\u3000\uFEFF| B" => "only no-break and full-width space",
      "A -->|\"\" | B" => "an empty pair of quotes",
      "A -->|\" \"| B" => "quotes round only space",
    }.each do |source, what|
      it "leaves #{what} as an edge with no label" do
        expect(edge_tuples(source)).to eq([["A", "B", nil, "arrow"]])
      end
    end

    it "gives every edge of an `&` group the text" do
      expect(edge_tuples("A & B -->|t| C & D").map { |e| e[2] })
        .to eq(%w[t t t t])
    end

    it "reads each label of a chain" do
      source = "A -->|one| B ==>|two| C -.->|three| D"

      expect(edge_tuples(source).map { |e| e[2] }).to eq(%w[one two three])
    end

    it "reads a label written around the link in the same chain" do
      source = "A -- one --> B -->|two| C == three ==> D"

      expect(edge_tuples(source).map { |e| e[2] }).to eq(%w[one two three])
    end

    it "labels only the edge that carries one" do
      expect(edge_tuples("A --> B -->|t| C --> D").map { |e| e[2] })
        .to eq([nil, "t", nil])
    end

    it "labels a named edge" do
      expect(edge_tuples("A e1@-->|t| B").map { |e| e[2] }).to eq(%w[t])
    end

    it "still refuses an empty pair of pipes, as mermaid does" do
      expect { parse_flowchart("A -->|| B") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "the SVG of a label written between pipes" do
    it "draws the text without the pipes" do
      svg = Sirena.render("flowchart LR\nA -->|yes| B\n")
      texts = svg.scan(%r{<text[^>]*>(.*?)</text>}m).flatten

      expect(texts.grep(/yes|\|/)).to eq(["yes"])
    end
  end
end
