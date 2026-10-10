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
end
