# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

module PlantUmlSequenceHelpers
  def wrap(*lines)
    "@startuml\n#{lines.join("\n")}\n@enduml\n"
  end

  def parse(*lines)
    Sirena::Notation::PlantUML::Sequence::Parser.new.parse(wrap(*lines))
  end

  def message_of(arrow)
    parse("A #{arrow} B : hi").messages.first
  end
end

RSpec.describe Sirena::Notation::PlantUML::Sequence::Parser do
  include PlantUmlSequenceHelpers

  let(:unsupported) do
    Sirena::Notation::PlantUML::UnsupportedConstructError
  end

  describe "participants" do
    {
      "participant" => :participant, "actor" => :actor,
      "boundary" => :boundary, "control" => :control, "entity" => :entity,
      "database" => :database, "collections" => :collections,
      "queue" => :queue, "Actor" => :actor
    }.each do |word, kind|
      it "reads #{word} as #{kind}" do
        expect(parse("#{word} A").participants.first.kind).to eq(kind)
      end
    end

    it "reads `X as Y` as label X and id Y" do
      participant = parse('participant "Long name" as L').participants.first

      expect([participant.label, participant.id]).to eq(["Long name", "L"])
    end

    it "orders participants by first mention, declared or not" do
      ids = parse("A -> B", "participant C", "C -> A").participants.map(&:id)

      expect(ids).to eq(%w[A B C])
    end

    it "keeps the first declaration when a name is declared twice" do
      kinds = parse("actor A", "participant A").participants.map(&:kind)

      expect(kinds).to eq([:actor])
    end
  end

  describe "messages" do
    {
      "->" => [:filled, false], "->>" => [:open, false],
      "-->" => [:filled, true], "-->>" => [:open, true]
    }.each do |arrow, (head, dashed)|
      it "reads #{arrow} as head #{head}, dashed #{dashed}" do
        message = message_of(arrow)

        expect([message.head, message.dashed]).to eq([head, dashed])
      end
    end

    {
      "<-" => [:filled, false], "<<-" => [:open, false],
      "<--" => [:filled, true], "<<--" => [:open, true]
    }.each do |arrow, (head, dashed)|
      it "reads #{arrow} as the reverse, head #{head}, dashed #{dashed}" do
        message = message_of(arrow)

        expect([message.from, message.to, message.head, message.dashed])
          .to eq(["B", "A", head, dashed])
      end
    end

    it "keeps the label as written" do
      expect(message_of("->").label).to eq("hi")
    end

    it "reads a message with no label" do
      expect(parse("A -> B").messages.first.label).to be_nil
    end

    it "reads a self message" do
      expect(parse("A -> A").messages.first).to be_self_message
    end

    it "reads a quoted endpoint without its quotes" do
      expect(parse('"A b" -> C').messages.first.from).to eq("A b")
    end
  end

  describe "boxes" do
    it "groups the participants declared inside" do
      box = parse('box "G"', "participant A", "endbox", "A -> B").boxes.first

      expect([box.title, box.members]).to eq(["G", ["A"]])
    end

    it "reads `end box` as the closer" do
      expect(parse("box", "participant A", "end box").boxes.size).to eq(1)
    end
  end

  describe "the wrapper" do
    it "skips comment lines and blank lines" do
      expect(parse("' note", "", "A -> B").messages.size).to eq(1)
    end

    it "refuses a diagram with no participant" do
      expect { parse("' nothing") }.to raise_error(unsupported, /empty/)
    end

    it "refuses a missing @enduml" do
      expect { described_class.new.parse("@startuml\nA -> B\n") }
        .to raise_error(Sirena::Parser::ParseError, /@enduml/)
    end

    it "refuses invalid UTF-8" do
      expect { described_class.new.parse("@startuml\nA -> \xFF\n@enduml") }
        .to raise_error(Sirena::Parser::ParseError, /UTF-8/)
    end

    it "refuses an unclosed box" do
      expect { parse("box", "participant A") }
        .to raise_error(Sirena::Parser::ParseError, /never closed/)
    end

    it "refuses a box around separated participants" do
      lines = ["A -> B", "box", "participant C", "participant A", "end box"]

      expect { parse(*lines) }
        .to raise_error(Sirena::Parser::ParseError, /neighbours/)
    end
  end

  describe "constructs outside the slice" do
    {
      "note over A: hi" => "note", "alt ok" => "alt",
      "activate A" => "activate", "== part ==" => "divider",
      "!pragma teoz true" => "preprocessor directive",
      "A ->x B" => "message arrow", "A -[#red]> B" => "message arrow",
      "participant A <<x>>" => "participant", "return ok" => "return",
      "title T" => "title"
    }.each do |line, name|
      it "refuses #{line.inspect} as #{name}" do
        expect { parse("A -> B", line) }
          .to raise_error(unsupported) { |e| expect(e.construct).to eq(name) }
      end
    end

    it "refuses a nested box" do
      expect { parse("box", "box", "participant A") }
        .to raise_error(unsupported, /nested box/)
    end

    it "reports the line of the refusal" do
      expect { parse("A -> B", "note over A: hi") }
        .to raise_error(unsupported) { |e| expect(e.line).to eq(3) }
    end
  end
end
