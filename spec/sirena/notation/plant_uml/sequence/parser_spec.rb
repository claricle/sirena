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

  def refusal_of(*lines)
    parse(*lines)
    nil
  rescue Sirena::Notation::PlantUML::UnsupportedConstructError => e
    e
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

  describe "pragmas" do
    it "accepts !pragma teoz true and keeps the messages" do
      diagram = parse("!pragma teoz true", "A -> B : hi")

      expect(diagram.messages.size).to eq(1)
    end

    it "still refuses another pragma by name" do
      expect { parse("!pragma layout smetana", "A -> B") }
        .to raise_error(unsupported, /preprocessor directive/)
    end
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
      "activate A" => "activate", "newpage" => "newpage",
      "!pragma layout smetana" => "preprocessor directive",
      "A ->x B" => "message arrow", "A -[#red]> B" => "message arrow",
      "participant A <<x>>" => "participant", "title T" => "title"
    }.each do |line, name|
      it "refuses #{line.inspect} as #{name}" do
        expect(refusal_of("A -> B", line)).to have_attributes(construct: name)
      end
    end

    it "refuses a nested box" do
      expect { parse("box", "box", "participant A") }
        .to raise_error(unsupported, /nested box/)
    end

    it "reports the line of the refusal" do
      expect(refusal_of("A -> B", "activate A"))
        .to have_attributes(line: 3)
    end
  end

  describe "notes" do
    def note_of(*lines)
      parse("A -> B", *lines).items.last
    end

    it "reads a one-line note over a participant" do
      note = note_of("note over A: hi")

      expect([note.side, note.targets, note.text]).to eq([:over, ["A"], "hi"])
    end

    it "reads a note over two participants" do
      expect(note_of("note over A, B: hi").targets).to eq(%w[A B])
    end

    it "joins the lines of a block note and keeps its comment-like lines" do
      note = note_of("note right of B", "one", "' two", "end note")

      expect(note.text).to eq("one\n' two")
    end

    it "reads hnote and rnote shapes" do
      shapes = %w[hnote rnote].map do |word|
        note_of("#{word} left of A: x").shape
      end

      expect(shapes).to eq(%i[hnote rnote])
    end

    it "reads a note across all participants" do
      expect(note_of("note across: x").side).to eq(:across)
    end

    it "ignores a colour after the side" do
      expect(note_of("note right #red: x").text).to eq("x")
    end

    it "attaches a note without a target to the message before it" do
      expect(note_of("note left: x")).to be_attached
    end

    it "refuses a note without a target that follows no message" do
      expect { parse("participant A", "note left: x") }
        .to raise_error(unsupported, /note/)
    end

    it "reads @enduml inside an open note as note text" do
      expect { parse("A -> B", "note left of A", "text") }
        .to raise_error(Sirena::Parser::ParseError, /missing @enduml/)
    end

    it "splits the characters backslash-n into lines" do
      expect(note_of("note over A: a\\nb").lines).to eq(%w[a b])
    end
  end

  describe "blocks" do
    def phases(*lines)
      fragment = Sirena::Notation::PlantUML::Sequence::Fragment
      parse("A -> B", *lines).items.grep(fragment)
        .map { |f| [f.phase, f.keyword, f.label] }
    end

    it "reads alt, else and end with their guards" do
      expect(phases("alt ok", "else bad", "end"))
        .to eq([[:open, "alt", "ok"], [:else, "alt", "bad"],
                [:close, "alt", nil]])
    end

    it "reads every block keyword" do
      words = %w[opt loop par critical break group]

      expect(words.map { |w| phases(w, "end").first[1] }).to eq(words)
    end

    it "drops the colour of a group" do
      expect(phases("group #ffa Setup", "end").first[2]).to eq("Setup")
    end

    it "nests blocks" do
      expect(phases("alt", "loop", "end", "end").map(&:first))
        .to eq(%i[open open close close])
    end

    it "refuses an end with nothing open" do
      expect { parse("A -> B", "end") }.to raise_error(unsupported, /end/)
    end

    it "refuses an else outside a block" do
      expect { parse("A -> B", "else") }.to raise_error(unsupported, /else/)
    end

    it "refuses a block that is never closed" do
      expect { parse("A -> B", "alt x") }
        .to raise_error(Sirena::Parser::ParseError, /block is never closed/)
    end
  end

  describe "return and dividers" do
    it "answers the last call with a dashed message the other way" do
      reply = parse("A -> B", "return ok").messages.last

      expect([reply.from, reply.to, reply.dashed, reply.label])
        .to eq(["B", "A", true, "ok"])
    end

    it "answers nested calls in reverse order" do
      senders = parse("A -> B", "B -> C", "return", "return").messages.last(2)

      expect(senders.map(&:from)).to eq(%w[C B])
    end

    it "refuses a return with nothing to answer" do
      expect { parse("A --> B", "return") }
        .to raise_error(unsupported, /return/)
    end

    it "reads a divider with its text" do
      divider = parse("A -> B", "== Phase ==").items.last

      expect(divider.label).to eq("Phase")
    end
  end
end
