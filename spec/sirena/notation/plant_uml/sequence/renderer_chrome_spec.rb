# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Renderer do
  include PlantUmlSequenceTitleHelpers

  let(:svg) do
    scene = laid_out("header H", "footer F", "caption C", "legend K",
                     "A -> B")
    described_class.new.render(scene).to_xml
  end

  def matches(xpath)
    REXML::XPath.match(REXML::Document.new(svg), xpath)
  end

  { "header" => "H", "footer" => "F", "caption" => "C",
    "legend" => "K" }.each do |id, text|
    it "draws the #{id} in a group of its own" do
      expect(matches("//g[@id='#{id}']//text").map(&:text)).to eq([text])
    end
  end

  it "frames the legend with a rounded grey box" do
    expect(matches("//g[@id='legend']/rect/@fill").map(&:value))
      .to eq(["#DDDDDD"])
  end

  it "draws header text in grey" do
    expect(matches("//g[@id='header']/text/@fill").map(&:value))
      .to eq(["#888888"])
  end
end
