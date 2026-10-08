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

  describe ".parse" do
    let!(:pie_handlers) { described_class.type_handlers(:pie) }
    let(:defaulted_handlers) do
      Hash.new { |_hash, key| pie_handlers.fetch(key) }
        .merge(parser: pie_handlers.fetch(:parser))
    end

    it "reads :transform and :renderer through the handler hash's own lookup" do
      allow(described_class).to receive(:type_handlers) { defaulted_handlers }
      parsed = described_class.parse("pie\n\"a\": 1")

      expect([parsed.transform, parsed.renderer])
        .to eq(pie_handlers.values_at(:transform, :renderer))
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

  describe ".clear_types" do
    let(:probe_handlers) do
      { parser: Object, transform: Object, renderer: Object, model: Object }
    end

    around do |example|
      snapshot = described_class.types.to_h do |type|
        [type, described_class.type_handlers(type).dup]
      end
      example.run
    ensure
      snapshot.each do |type, handlers|
        described_class.register_type(type, **handlers)
      end
    end

    it "empties the type table" do
      described_class.clear_types

      expect(described_class.types).to be_empty
    end

    it "swaps in a new table instead of emptying the old one" do
      returned = described_class.clear_types
      described_class.register_type(:probe, **probe_handlers)
      described_class.clear_types

      expect(returned).to include(:probe)
    end

    it "is what DiagramRegistry.clear empties" do
      Sirena::DiagramRegistry.clear

      expect(described_class.types).to be_empty
    end

    it "makes a rendering fail until the types are registered again" do
      described_class.clear_types

      expect { Sirena.render("pie\n\"a\": 1") }.to raise_error(
        Sirena::Engine::DiagramTypeError,
        /No handlers registered for diagram type: pie/,
      )
    end
  end
end
