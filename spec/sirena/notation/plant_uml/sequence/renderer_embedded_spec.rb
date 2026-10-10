# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Renderer do
  include PlantUmlSequenceTitleHelpers

  let(:svg) do
    scene = laid_out("title T", *nested_note("scale 2", "X -> Y"))
    described_class.new.render(scene).to_xml
  end

  def matches(xpath)
    REXML::XPath.match(REXML::Document.new(svg), xpath)
  end

  it "draws the embedded diagram scaled inside the note" do
    expect(matches("//g[@transform]/@transform").map(&:value))
      .to include(a_string_matching(/scale\(2\.0\)/))
  end

  it "draws the title in bold" do
    expect(matches("//g[@id='title']/text/@font-weight").first.value)
      .to eq("bold")
  end
end
