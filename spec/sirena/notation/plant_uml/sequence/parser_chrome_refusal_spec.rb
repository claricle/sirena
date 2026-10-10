# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Parser do
  include PlantUmlSequenceTitleHelpers

  {
    ["header **H**"] => "header",
    ["footer Page %page%"] => "footer",
    ["caption <b>C</b>"] => "caption",
    ["title", "**T**", "end title"] => "title",
    ["header", "", "end header"] => "header",
    ["legend", "| a | b |", "end legend"] => "legend",
    ["title", "end title"] => "title",
    ["left header Top"] => "aligned header or footer",
    ["center footer Bot"] => "aligned header or footer",
  }.each do |lines, construct|
    it "refuses #{lines.join(' / ').inspect} as #{construct}" do
      expect(refusal_for(*lines, "A -> B"))
        .to have_attributes(construct: construct)
    end
  end

  it "reports a block that is never closed" do
    expect { parsed_diagram("legend", "Key") }
      .to raise_error(Sirena::Parser::ParseError, /never closed/)
  end

  it "does not close a header block with end legend" do
    expect(refusal_for("header", "One", "end legend", "A -> B"))
      .to have_attributes(construct: "header")
  end
end
