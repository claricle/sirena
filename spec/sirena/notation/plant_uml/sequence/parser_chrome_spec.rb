# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Parser do
  include PlantUmlSequenceTitleHelpers

  def chrome_of(*lines)
    parsed_diagram(*lines, "A -> B").chrome
  end

  {
    "header Top" => :header,
    "footer Bot" => :footer,
    "caption Cap" => :caption,
    "legend Key" => :legend,
  }.each do |line, kind|
    it "reads the one-line #{kind}" do
      expect(chrome_of(line).lines(kind)).to eq([line.split.last])
    end
  end

  %i[header footer caption legend].each do |kind|
    it "reads the #{kind} block" do
      chrome = chrome_of(kind.to_s, "One", "Two", "end #{kind}")

      expect(chrome.lines(kind)).to eq(%w[One Two])
    end
  end

  it "reads a title block as lines" do
    expect(parsed_diagram("title", "One", "Two", "end title", "A -> B").title)
      .to eq("One\nTwo")
  end

  it "accepts endtitle without a space" do
    expect(parsed_diagram("title", "One", "endtitle", "A -> B").title)
      .to eq("One")
  end

  {
    "legend" => "bottom center",
    "legend left" => "bottom left",
    "legend right" => "bottom right",
    "legend top" => "top center",
    "legend top left" => "top left",
    "legend bottom right" => "bottom right",
  }.each do |line, place|
    it "places #{line.inspect} at #{place}" do
      chrome = chrome_of(line, "Key", "end legend")

      expect(chrome.legend_place).to eq(place)
    end
  end

  it "keeps the legend place when a footer is read after it" do
    chrome = chrome_of("legend top", "Key", "end legend", "footer F")

    expect(chrome.legend_place).to eq("top center")
  end

  it "keeps a participant called header" do
    expect(parsed_diagram("header -> B : x").messages.size).to eq(1)
  end
end
