# frozen_string_literal: true

require "spec_helper"
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
