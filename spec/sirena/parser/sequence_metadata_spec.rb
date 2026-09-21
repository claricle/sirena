# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require "sirena/parser/sequence"

# Corpus bucket "diagram metadata statements": mmdc renders every sequence
# diagram below; sirena raised a ParseError at the first `title`, `accTitle`,
# `accDescr` or `autonumber` line. These statements are accepted and
# contribute no participants, messages or notes, so the diagram drawn from
# the lines around them is unchanged.
RSpec.describe Sirena::Parser::SequenceParser do
  let(:parser) { described_class.new }
  let(:body) { "Alice->Bob:Hello Bob\nNote right of Bob: Bob thinks\n" }
  let(:plain) { parser.parse("sequenceDiagram\n#{body}") }

  {
    "title with a colon" => "title: Diagram Title",
    "title without a colon" => "title Diagram Title",
    "accTitle" => "accTitle: This is the title",
    "accDescr on one line" => "accDescr: Accessibility Description",
    "accDescr block" => "accDescr {\nAccessibility\nDescription\n}",
    "autonumber" => "autonumber",
    "autonumber with a start" => "autonumber 10",
    "autonumber with a start and step" => "autonumber 10 5",
    "autonumber off" => "autonumber off",
    "autonumber with decimal start and step" => "autonumber 1.5 0.25",
    "autonumber with a leading-dot step" => "autonumber 1 .5",
    "title followed by a semicolon" => "title Diagram Title;",
    "autonumber with a trailing comment" => "autonumber %% numbered"
  }.each do |name, line|
    it "accepts #{name} without changing the diagram around it" do
      diagram = parser.parse("sequenceDiagram\n#{line}\n#{body}")

      expect(diagram.participants.map(&:id)).to eq(plain.participants.map(&:id))
      expect(diagram.messages.size).to eq(plain.messages.size)
      expect(diagram.notes.size).to eq(plain.notes.size)
    end
  end

  it "accepts a diagram holding nothing but metadata" do
    diagram = parser.parse("sequenceDiagram\ntitle T\nautonumber\n")

    expect(diagram.messages).to eq([])
  end

  it "accepts metadata after the first message" do
    diagram = parser.parse("sequenceDiagram\nAlice->Bob: hi\nautonumber\nBob->Alice: yo\n")

    expect(diagram.messages.size).to eq(2)
  end

  # mermaid's lexer ends `title` text and an `autonumber` line at `;`, which
  # is a statement separator, so the statement after it is still parsed.
  describe "a semicolon after title or autonumber separates statements" do
    {
      "title" => "title T;Alice->Bob: hi",
      "title with a colon" => "title: T;Alice->Bob: hi",
      "autonumber" => "autonumber;Alice->Bob: hi",
      "autonumber with a start" => "autonumber 3;Alice->Bob: hi"
    }.each do |name, source|
      it "keeps the message after #{name}" do
        diagram = parser.parse("sequenceDiagram\n#{source}\n")

        expect(diagram.messages.size).to eq(1)
      end
    end
  end

  # A run of interior spaces made `rest_of_line` rescan the whole run at
  # every character: 2560 spaces took about 1.5s, doubling the input
  # quadrupled the time. Linear parsing finishes in milliseconds.
  describe "text with a long run of interior spaces" do
    {
      "title" => "title x",
      "accTitle" => "accTitle: x",
      "accDescr" => "accDescr: x"
    }.each do |name, prefix|
      it "parses a #{name} line in linear time" do
        source = "sequenceDiagram\n#{prefix}#{' ' * 2560}y\nAlice->Bob: hi\n"
        elapsed = Benchmark.realtime { parser.parse(source) }

        expect(elapsed).to be < 0.5
      end
    end
  end

  # Guards, green without the metadata rules: keep them, they go red the
  # moment a metadata rule stops requiring `line_end` and starts stealing
  # messages from participants named like a keyword.
  describe "participants named like a metadata keyword stay participants" do
    it "keeps `autonumber` as a message endpoint" do
      diagram = parser.parse("sequenceDiagram\nautonumber->>Bob: hi\n")

      expect(diagram.participants.map(&:id)).to eq(%w[autonumber Bob])
    end

    it "keeps `title` as a message endpoint" do
      diagram = parser.parse("sequenceDiagram\ntitle->>Bob: hi\n")

      expect(diagram.participants.map(&:id)).to eq(%w[title Bob])
    end

    it "keeps `accTitle` as a message endpoint" do
      diagram = parser.parse("sequenceDiagram\naccTitle->>Bob: hi\n")

      expect(diagram.participants.map(&:id)).to eq(%w[accTitle Bob])
    end
  end

  # Guard, green without the metadata rules: keep it, it goes red if the
  # accDescr block rule ever accepts a block with no closing brace.
  describe "malformed metadata still fails" do
    it "rejects an unterminated accDescr block" do
      expect { parser.parse("sequenceDiagram\naccDescr {\nnever closed\nAlice->Bob: hi\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end
end
