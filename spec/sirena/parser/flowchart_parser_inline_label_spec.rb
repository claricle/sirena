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

    {
      "A -- a -- b --> C" => "a doubled hyphen in the text",
      "A -- --> C" => "a label that is only space",
      "A -- text -- B" => "a link that never closes",
      "A o-- t --> B" => "an opening o that is not closed",
      "A x-- t --> B" => "an opening x that is not closed",
      "A x== t ==> B" => "an opening x on a thick link",
      "A o== t ==> B" => "an opening o on a thick link",
      "A o-- t --x B" => "an o closed by an x",
      "A == a=b ==> B" => "a lone = in a thick label",
      "A -. a.b .-> B" => "a dot in a dotted label",
      "A -- \u00A0 --> B" => "a label of only no-break spaces"
    }.each do |source, reason|
      it "refuses #{source.inspect}, #{reason}" do
        expect { edge_tuples(source) }.to raise_error(Sirena::Parser::ParseError)
      end
    end

    it "keeps a marker matched at both ends" do
      expect(edge_tuples("A x-- t --x B")).to eq([["A", "B", "t", "cross_both"]])
    end

    {
      "A -- t <--> B" => "arrow_both",
      "A == t <==> B" => "thick_arrow_both",
      "A -. t <.-> B" => "dotted_arrow_both",
      "A -- t <--x B" => "cross"
    }.each do |source, arrow_type|
      it "reads the start head of #{source.inspect}" do
        expect(edge_tuples(source).first.last).to eq(arrow_type)
      end
    end

    ["A -- t\n--> B", "A -- t\r\n--> B", "A -- t\r--> B"].each do |source|
      it "reads #{source.inspect} as one labelled edge" do
        expect(edge_tuples(source)).to eq([["A", "B", "t", "arrow"]])
      end
    end

    it "trims the no-break spaces around a label" do
      expect(edge_tuples("A --\u00A0text\u00A0--> B").first[2]).to eq("text")
    end

    it "drops a comment line from a label that spans lines" do
      expect(edge_tuples("A -- text\n%% comment\n--> B").first[2])
        .to eq("text")
    end

    it "keeps the lines of a label that spans them" do
      expect(edge_tuples("A -- one\ntwo\n--> B").first[2]).to eq("one\ntwo")
    end

    {
      "spaces" => "A -- a#{' ' * 20_000}b --> B",
      "dots of an unclosed dotted label" => "A -. a#{'.' * 20_000}",
      "equals of an unclosed thick label" => "A == a#{'=' * 20_000}"
    }.each do |what, source|
      it "parses a long run of #{what} in linear time" do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          edge_tuples(source)
        rescue Sirena::Parser::ParseError
          nil
        end
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
          .to be < 2
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
