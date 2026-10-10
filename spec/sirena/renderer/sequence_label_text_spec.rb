# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

module SequenceLabelTextHelpers
  module_function

  def drawn_texts(source)
    doc = REXML::Document.new(Sirena::Engine.new.render(source))
    REXML::XPath.match(doc, "//*[local-name()='text']").flat_map do |node|
      runs = node.get_elements("tspan")
      runs.empty? ? [node.texts.map(&:value).join] : runs.map(&:text)
    end
  end
end

RSpec.describe Sirena::Renderer::Sequence do
  # Reference texts: spec/fixtures_mermaid/sequence/ cases 019, 030, 031, 032.
  {
    "wrap: prefix" => ["Alice->>Bob:wrap: Hello there", "Hello there"],
    "nowrap: prefix" => ["Alice->>Bob:nowrap: one line", "one line"],
    "<br> break" => ["Alice->>Bob: multiline<br>text", "multiline"],
    "<br/> break" => ["Alice->>Bob: multiline<br/>text", "multiline"],
    "<br /> break" => ["Alice->>Bob: multiline<br />text", "multiline"],
    "numeric entity" => ["A->>B: I #9829; you!", "I ♥ you!"],
    "named entity" => ["A->>B: you #infin; times", "you ∞ times"],
  }.each do |name, (line, expected)|
    it "draws a message with #{name} as #{expected.inspect}" do
      source = "sequenceDiagram\n#{line}\n"

      expect(SequenceLabelTextHelpers.drawn_texts(source)).to include(expected)
    end
  end

  describe "a wrapped message" do
    let(:wrapped_source) do
      "sequenceDiagram\nA->>B:wrap: #{'word ' * 30}\n"
    end
    let(:runs) do
      doc = REXML::Document.new(Sirena::Engine.new.render(wrapped_source))
      REXML::XPath.match(doc, "//*[local-name()='tspan']")
    end

    it "draws more than one line" do
      expect(runs.length).to be > 1
    end

    it "places every line with its own y" do
      expect(runs.map { |run| run.attributes["y"] }).to all(match(/\A\d/))
    end

    it "centres every line on the text's own x" do
      xs = runs.map { |run| run.attributes["x"] }

      expect(xs).to all(eq(runs.first.parent.attributes["x"]))
    end

    it "writes no dy on any line" do
      expect(runs.map { |run| run.attributes["dy"] }).to all(be_nil)
    end

    it "steps each line down by the drawn pitch" do
      ys = runs.map { |run| run.attributes["y"].to_f }

      expect(ys.each_cons(2).map { |top, low| low - top }.uniq).to eq([19.0])
    end
  end
end
