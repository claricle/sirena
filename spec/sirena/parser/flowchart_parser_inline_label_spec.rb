# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::FlowchartParser do
  include FlowchartParserHelpers

  describe "a label written inside the link" do
    {
      "A-- text -->B" => "arrow",
      "A -- text --> B" => "arrow",
      "A-- text --- B" => "line",
      "A-- text --x B" => "cross",
      "A-- text --o B" => "circle",
      "A<-- text -->B" => "arrow_both",
      "A== text ==>B" => "thick_arrow",
      "A== text === B" => "thick_line",
      "A-. text .->B" => "dotted_arrow",
      "A-. text .- B" => "dotted_line"
    }.each do |source, arrow_type|
      it "reads #{source.inspect} as one #{arrow_type} edge" do
        expect(edge_tuples(source)).to eq([["A", "B", "text", arrow_type]])
      end
    end

    it "keeps a hyphen, a slash and a keyword in the text" do
      expect(edge_tuples("A -- text with / and graph-y words --x B"))
        .to eq([["A", "B", "text with / and graph-y words", "cross"]])
    end

    it "chains onto the next edge" do
      expect(edge_tuples("A-- one -->B-- two -->C").map { |e| e[2] })
        .to eq(%w[one two])
    end

    it "leaves `A --x B` a cross-headed link with no label" do
      expect(edge_tuples("A --x B")).to eq([["A", "B", nil, "cross"]])
    end

    ["A -- a -- b --> C", "A -- --> C", "A -- text -- B", "A -- text\n--> B"]
      .each do |source|
      it "refuses #{source.inspect}, which mermaid cannot lex" do
        expect { edge_tuples(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "the flowchart corpus cases behind the inline-label bucket" do
    Dir[File.join(__dir__, "../../mermaid/flowchart/*.mmd")].select do |f|
      File.basename(f).match?(
        /\A((031|033|035)_parser_should_handle_double|163|164|17[3-9]|18[0-5])_/
      )
    end.each do |path|
      it "renders #{File.basename(path, '.mmd')}" do
        expect { Sirena::Engine.new.render(File.read(path)) }
          .not_to raise_error
      end
    end
  end
end
