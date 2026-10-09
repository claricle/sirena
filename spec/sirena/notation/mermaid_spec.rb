# frozen_string_literal: true

require "spec_helper"

module MermaidSpecHelpers
  def detects?(source)
    body = Sirena::Source.split(source)[:body]
    Sirena::Notation::Mermaid.detect_type(body)
    true
  rescue Sirena::Engine::DiagramTypeError
    false
  end
end

RSpec.describe Sirena::Notation::Mermaid do
  include MermaidSpecHelpers

  describe ".id" do
    it "names the notation" do
      expect(described_class.id).to eq(:mermaid)
    end
  end

  describe ".extensions" do
    it "is .mmd alone" do
      expect(described_class.extensions).to eq([".mmd"])
    end

    it "is frozen" do
      expect(described_class.extensions).to be_frozen
    end
  end

  describe ".detect_type" do
    it "refuses a source that opens with no diagram keyword" do
      expect { described_class.detect_type("hello") }.to raise_error(
        Sirena::Engine::DiagramTypeError,
        /\AUnable to detect diagram type from source\./,
      )
    end

    it "names the type a source opens with" do
      expect(described_class.detect_type("pie\n")).to eq(:pie)
    end
  end

  describe ".claims?" do
    {
      "a bare keyword" => "graph TD\nA-->B",
      "a keyword behind frontmatter, a directive and a comment" =>
        ["---", "title: T", "---", "%%{init: {}}%%", "%% note",
         "sequenceDiagram", "A->>B: hi"].join("\n"),
      "a binary-tagged source" => "graph TD\nA-->B".b,
      "a keyword after an invalid byte on a later line" =>
        "%% \xff\nflowchart LR\nA-->B",
      "a keyword with a byte order mark" => "\uFEFFpie\n\"a\": 1",
    }.each do |label, source|
      it "claims #{label}" do
        expect(described_class.claims?(source)).to be(true)
      end
    end

    {
      "plain text" => "hello",
      "an empty String" => "",
      "a keyword only inside a comment" => "%% graph TD\nhello",
      "PlantUML" => "@startuml\nA -> B\n@enduml",
    }.each do |label, source|
      it "does not claim #{label}" do
        expect(described_class.claims?(source)).to be(false)
      end
    end

    [
      "flowchart-elk TD", "graph>", "sequenceDiagram", "stateDiagram-v2",
      "radar-beta", "treemap-beta", "C4Context", "gitGraph", "journey",
      "xychart-beta", "info", "error", "graphs", "flowchart-ELK",
      "\xff graph TD".b, "unknownDiagram", " \n  pie\n"
    ].each do |source|
      it "agrees with detect_type for #{source.inspect}" do
        expect(described_class.claims?(source)).to be(detects?(source))
      end
    end
  end

  describe ".type_registered?" do
    it "is true for a registered type" do
      expect(described_class.type_registered?(:pie)).to be(true)
    end

    it "is false for an unknown type" do
      expect(described_class.type_registered?(:no_such_type)).to be(false)
    end
  end
end
